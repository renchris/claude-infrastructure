# O6 — THE OVERSIGHT MATRIX: 7 unit classes × SEE / INTERRUPT / STOP / AUDIT, and what we already built

**Date:** 2026-08-19 · **Box:** MacBookPro18,2 (M1 Max, hw.ncpu=10, 64 GiB) · **Binary:** Claude Code 2.1.220
**Question this axis serves:** *how do we have >15 units we WANT OVERSIGHT ON, without things blindly going on by themselves?*
**Read-only.** No live pane, session or process was killed, stopped, keyed or reconfigured. Every config read was a read.
**Builds on** `docs/research/orchestration-units-2026-08-19.md` (4a3bd3373) + its `A5-our-slot-accounting.md`. Where I contradict them I say so.
Labels: **MEASURED** (I ran it) · **INFERRED** (read the code/binary, did not execute the path) · **QUOTED** (vendor text) · **NONE**.

---

## 1. VERDICT (≤5 lines)

1. **Oversight is not one property and our stack only ever bought ONE of the four.** Every rail we own is addressed by a **pane**, so a paneless unit scores NONE on SEE, INTERRUPT and STOP simultaneously — and AUDIT survives only because transcripts are written whether or not anyone can find them.
2. **The pane is not what makes a unit overseeable; the ADDRESS is.** MEASURED: `cc-teardown` takes `<pane-uuid|name>` (`bin/cc-teardown:187`) — a unit with no pane is unaddressable *by construction*, not by accident. That single line is why the whole right-hand side of the matrix is empty.
3. **Anthropic already ships oversight for the two units we call ungoverned, and we do not use either.** MEASURED: `claude agents --json` enumerates live sessions across all four accounts without a TTY; and the binary carries, verbatim, *"Stop a running workflow at any time with `/workflows`"*. The landed doc's "a running Workflow has NO abort path" is true of **our** tooling and **false of the product** — the lever exists, is operator-only, TUI-only, and invisible to every rail we own.
4. **Our own admission surface is bigger than we documented and still misses the same unit.** MEASURED: `hooks/agent-teams-enforce.sh` holds **8** deny sites (not 6) + `frontier-spawn-gate.sh` = **9 gates**, of which a Workflow agent fires **0**.
5. **AUDIT is the cell that looks fine and is not.** MEASURED on one completed run: **6 agents started, 5 did work, 3 recorded a result**; one agent produced zero assistant turns and left no record of why; and our own `bash-commands.log` filed **516 of the last 5,000 rows under ONE session uuid** — this wave's lead — so nothing on disk can say which of ~16 agents ran a given command.

---

## 2. THE MATRIX — 7 unit classes × 4 capabilities

**Definitions used throughout.** **SEE** = know a unit's state without going to look at it · **INTERRUPT** = be pulled in when, and only when, it needs a human · **STOP** = halt or redirect it, at any time, from one place · **AUDIT** = reconstruct afterwards what it did and why.

Where a cell is NONE I say **by-accident** (nobody wired it; a patch closes it) or **by-construction** (the unit has no addressable identity in that channel; a patch cannot close it without first minting an address).

### 2a. SEE

| Unit | Mechanism | Verdict | Evidence / command |
|---|---|---|---|
| **1. Pane session** | kitty/iTerm2 pane + `cc-where` (renders window id, cols, conversation title, activity glyph) + CC-native `sessions/<pid>.json` + `claude agents --json` + statusline (self only) | **MEASURED — good** | `cc-where` → `12 panes · 0 off-screen · 7 squeezed under 80 cols`, each row `win 388  ⠂ Investigate agent orchestration…` |
| **2. Named teammate** `Agent({name})` | its own kitty pane, so `cc-where` renders it — **but under a title, not as a teammate**; it is NOT in CC's own registry | **MEASURED — partial** | `cc-where` shows rows titled `deep-research` and `Explore` (teammate panes). Registry: both live `--agent-id` procs (17602, 81402) absent from `sessions/*.json` and from `claude agents --json` — **0 of 2** |
| **3. Unnamed subagent** `Agent()` | none of ours. Inline in the lead's own TUI transcript while the lead's pane is on screen | **NONE — by-construction** | mints no process, no pane, no pid ⇒ nothing pid- or pane-keyed can hold it. `ps` census (below) shows 18 claude procs while ≥16 agents were live in this wave |
| **4. Workflow agent** `agent()` | **product-side only**: `/workflows` view (`" /workflows to stop"`, `"to view dynamic workflow runs"`, statuses `Running in background / Failed / Stopped / Completed`) rendered in the PARENT pane | **MEASURED (binary read) — exists, not scriptable** | `LC_ALL=C strings -a -n 4 claude.exe > /tmp/o6-strings.txt` then `grep -n '/workflows to stop'` → line 581754, adjacent ` Large workflow `; `grep 'to view dynamic workflow runs'` present |
| **5. `--bg` worker** | CC's own `sessions/<pid>.json` (`kind:"bg"`) + the background-session view the operator screenshotted + `claude agents --json --all` | **INFERRED here / MEASURED upstream** | landed doc measured 3 rows one per live bg worker. **My snapshot had zero bg workers**, so I could not reproduce it — see §6 |
| **6. Headless `claude -p`** | nothing. Excluded from `k` **by design** (`-p/--print` filtered in argv[1..6], `bin/claude-accounts:499-504`); writes a transcript | **NONE — by-accident** | it HAS a pid and a session id; nothing reads them |
| **7. Cloud `--cloud`** | `cc-where` models it: 16 rows `kind=offbox … state=UNKNOWN action=open https://claude.ai/code/<id>` | **MEASURED — addressable, stateless** | `cc-where`. Every row's `state` is literally `UNKNOWN`: we can name them and open them, we cannot read them |

### 2b. INTERRUPT (be pulled in when, and only when, a human is needed)

| Unit | Mechanism | Verdict | Evidence |
|---|---|---|---|
| **1. Pane session** | CC writes `waitingFor` into `sessions/<pid>.json`; our `cc-permission-beacon.sh` + `notify.sh` + `cc-inbox-guard` | **MEASURED — the channel exists** | Value domain read out of the binary: `cjS = {…:"input needed", …:"dialog open"}` with fallback `?? "permission prompt"` ⇒ **`waitingFor ∈ {permission prompt, input needed, dialog open}`**. In my snapshot no session was waiting, so the field was absent from all 11 rows |
| **2. Named teammate** | our mailbox + `notify.sh` (teammate runs full lifecycle hooks incl. SessionStart) | **INFERRED** | teammate has its own hook set (landed doc §2). Not in CC's registry ⇒ its `waitingFor` is unreachable to the product surface |
| **3. Unnamed subagent** | the lead is BLOCKED on it; a permission prompt surfaces in the LEAD's pane | **MEASURED — by inheritance, not by identity** | this is the good case: an in-process agent cannot silently wait, because the tool call is synchronous in the lead's turn |
| **4. Workflow agent** | same inheritance — the `Workflow` tool call blocks the parent turn — **plus** a pre-flight approval dialog | **MEASURED (binary read)** | dialog title `"Run a dynamic workflow?"`, body *"This dynamic workflow will spin up multiple subagents across the following phases:"*, options `Yes, run it` / `Yes, and don't ask again for <name> in <scope>` / `View workflow summary` / `View raw script` / `No`. It computes `estimatedAgents` from the script (`p += kind==="sequential" ? m : m*3`) |
| **5. `--bg` worker** | CC's `waitingFor:"permission prompt"` in its registry row + the bg view's `"1 awaiting input"` counter | **QUOTED (operator screenshot) + INFERRED** | 🚨 **our** path is broken here: landed doc measured 3/3 bg sessions arming `cc-await-ping <uuid>` on a session with **no pane**, i.e. a wake that can never fire |
| **6. Headless `-p`** | **NONE** | **NONE — by-construction** | no TTY, no prompt surface; a permission need is a failure, not a question |
| **7. Cloud** | claude.ai web/mobile notification | **QUOTED** | not verified from this box |

### 2c. STOP (halt or redirect, at any time, from one place)

**This is the column the operator's question is actually about, and it is the emptiest.**

| Unit | Mechanism | Verdict | Evidence |
|---|---|---|---|
| **1. Pane session** | `cc-teardown <pane-uuid\|name> --done-evidence …`; `handoff-fire.sh self-close`; Esc/ctrl-c in the pane | **MEASURED — full** | `bin/cc-teardown:187`; verdict tokens `0 torn-down · 10 DEFER · 2 REFUSE · 5 FAIL · 6 INDETERMINATE` (`:188`) |
| **2. Named teammate** | structured `shutdown_request`; `cc-teardown --assignee-of <lead-sid>` (pane-uuid ONLY — an agent NAME is refused, `reason_kind=target-not-a-pane-uuid`) | **MEASURED — full but pane-addressed** | `bin/cc-teardown:192-196` |
| **3. Unnamed subagent** | Esc in the lead's pane aborts the turn — **all-or-nothing**; no per-agent stop | **MEASURED (binary) — coarse only** | binary carries `[interrupt] Aborting current turn: streamMode=`, `canInterruptTurn`, `[Request interrupted by user for tool use]`. There is no per-subagent handle to name |
| **4. Workflow agent** | 🚨 **`/workflows` — a real product stop, operator-only, TUI-only** · `disableWorkflows` managed setting as a kill switch · `budget.total` at author time | **MEASURED (binary, verbatim)** | *"Dynamic workflows can use a lot of tokens quickly by running many subagents in parallel — which counts against your usage limit. **Stop a running workflow at any time with `/workflows`**, or disable dynamic workflows in `/config`."* Also `Dynamic workflow cancelled`, `Workflow aborted`, `workflow-abort`, `The workflow stopped before this agent finished.`, and `Dynamic workflows are disabled by managed settings (\`disableWorkflows\`).` |
| **5. `--bg` worker** | product-side retire/evictor; **ours: NONE** — `cc-teardown` needs a pane, the reaper is pane-keyed | **NONE (ours) — by-construction** | landed doc: 3 bg workers survived `claude stop` by ~13 min and needed `kill -9` |
| **6. Headless `-p`** | `kill <pid>` — outside every sanctioned rail | **NONE (ours) — by-accident** | it has a pid we deliberately filter out of the census |
| **7. Cloud** | claude.ai UI. API path exists but is API-key-scoped: `POST /v1/sessions/$SESSION_ID/events` with `{"type":"user.interrupt"}` | **QUOTED (docs embedded in the binary)** | read at `/tmp/o6-strings.txt:620964` `## Interrupt a Running Session`. Our cloud sessions are subscription-auth, so this path is **EXISTS, not REACHABLE** for us |

**The rule the column states:** *a unit is STOPPABLE exactly when it has a name in a namespace the operator can type.* Pane uuid → yes. Agent id → no (refused by name, `cc-teardown:194`). Workflow run id → only inside the parent's TUI. Bg job id → exists in `jobs/<short>/state.json`, nothing reads it.

### 2d. AUDIT (reconstruct afterwards what it did and why)

| Unit | Durable record | Verdict | Evidence |
|---|---|---|---|
| **1. Pane session** | `<config>/projects/<slug>/<sid>.jsonl` + git + `idl.jsonl` + `bash-commands.log` + `pane-spawns.jsonl` | **MEASURED — good** | — |
| **2. Named teammate** | its own session transcript at slug level; pane-spawn row `chain:"handoff-fire.sh>it2-kitty"` vs bare `it2-kitty` | **MEASURED — good** | landed doc reconstructed a 3-generation cascade from `logs/pane-spawns.jsonl` |
| **3. Unnamed subagent** | `…/<sid>/subagents/agent-<id>.jsonl` (depth 3) | **MEASURED — present, unindexed** | — |
| **4. Workflow agent** | `…/<sid>/subagents/workflows/wf_<id>/agent-<id>.jsonl` (depth 5) + a 48-byte `.meta.json` + a `journal.jsonl` | **MEASURED — present, unindexed, and the journal UNDER-RECORDS** | §5 |
| **5. `--bg` worker** | conversation survives on disk and resumes; `jobs/<short>/state.json` has **no pid field at all** (24 keys enumerated by the landed doc's verifier) | **MEASURED (upstream)** | — |
| **6. Headless `-p`** | a normal transcript | **MEASURED** | — |
| **7. Cloud** | remote; `cc-cloud list` holds declarations. `cc-where` reports `state=UNKNOWN` for all 16 | **PARTIAL** | `cc-where` |

**The blindness that spans rows 3, 4 and 6:** our own execution log is session-keyed, and an in-process agent shares the lead's session id.

```
$ tail -5000 ~/.claude/logs/bash-commands.log | grep -o '^\[[0-9T:-]*Z\] \[[0-9a-f-]*\]' | sed 's/.*\] \[//;s/\]//' | sort | uniq -c | sort -rn | head -3
 516 f285654f-850c-4ada-96b5-407c5c01ccf0     ← THIS wave's lead; ~16 agents behind it
 380 020aafc9-88f5-4dc0-ac6c-33c6bd961b0e
  31 161874bb-37f6-4bbd-8c55-9c7d5e3451a6
```

Positive control that the field is genuinely absent rather than mis-grepped: `grep -c 'agentId' ~/.claude/logs/bash-commands.log` → **12**, and all twelve are commands whose *text* contains the word. The log schema is `[timestamp] [session-uuid] <command>` — there is no agent column.

---

## 3. WHAT WE ALREADY OWN — the honest coverage table

*This repo's standing failure mode is building a second thing beside a working one (`inventory-before-building`). So: what exists, what it covers, and what it structurally cannot see.*

| Tool | Address space | Covers | **Cannot see** |
|---|---|---|---|
| **`bin/cc-panes`** | — | — | 🚨 **DOES NOT EXIST.** `command -v cc-panes` → MISSING; `ls bin/cc-panes` → no such file; `git log --all --diff-filter=A -- 'bin/cc-panes*'` → **empty**. It is named in 3 docs (`docs/plans/CLOUD_OBSERVABILITY.md`, `docs/runbooks/cloud-fleet.md`, `docs/research/backlog-pipeline-recon-2026-08-12/recon-cloud.md`) and in task #145 ("build cc-panes census + jump") marked completed. **A spec-named mechanism that is prose only** (memory: `spec-named-mechanism-may-be-prose-only`). Its function lives in `cc-where` |
| **`bin/cc-where`** | kitty window id + `offbox` session id | 12 panes with os-window/tab/screen-position/width + conversation title + activity glyph; 16 cloud sessions with a clickable URL | teammates appear but are **not labelled as teammates**; **no** in-process agent, **no** workflow agent, **no** `--bg` worker; cloud `state=UNKNOWN` always |
| **`bin/cc-pane`** | iTerm2/kitty pane id | spawn/close/address a pane | anything paneless (11 pane-keyed tokens in 253 lines) |
| **`bin/cc-discover`** | plan/backlog rows | mints candidate work | nothing about live units. (Ran it: 8 candidates, then `line 138: Terminated: 15` — its own backlog call timed out) |
| **`bin/cc-reaper`** | pane / worktree | reaps stranded panes + worktrees | a paneless worker; landed doc: cannot reap a bg worker |
| **`bin/cc-teardown`** | **`<pane-uuid\|name>`** (`:187`) | the ONLY sanctioned stop; 5-valued verdict token | **refuses an agent NAME by design** (`:194`); no workflow, no subagent, no bg job |
| **`bin/cc-custody`** | fire marker keyed on firing cwd | open/return debt per dispatched fire — the one rail that makes an unreturned wave block a ✅ | a unit that was never *fired* opens no custody: subagents, workflow agents and teammates are all invisible to it **by design** |
| **`bin/cc-backlog`** | item id | what should happen | what IS happening |
| **`bin/cc-do`** | runnable operator steps | see the verbatim render below | live units — it is a to-do list, not a monitor |
| **`hooks/operator-readout.sh`** | session id | renders the operator close block from disk truth | an in-process agent shares its lead's sid ⇒ N agents render as 1 |
| **`scripts/wrap-ledger.sh`** | git + session id | ⛔/📤/🔧/📦/🚀/👤/✅ for **this** session | the same sid collapse; no notion of a child unit |
| **`scripts/assignee-pane-residency.sh`** | argv position + known member set | teammate panes, anchored on argv[0] (correctly avoids the `pgrep -f` trap) | paneless everything |
| **the registry** (`hooks/live-session-registry.sh`) | worktree basename → claude-ancestor pid, in `~/.reso/live-sessions` | keeps the worktree-GC from reaping a live session's tree | scoped to `~/Development/.worktrees/*` **only** (`case "$cwd" in "$HOME/Development/.worktrees/"*) ;; *) exit 0`), one row per worktree — it is a GC interlock, not a census |
| **the mailbox** | pane id / session uuid | peer mail, drained at every turn boundary | pane-keyed wake ⇒ a paneless unit arms a wake that can never fire (3/3 measured, landed doc) |
| **the statusline** | self | own context %, own account | every other unit |

**Answer to the axis's direct question — which of these handle a PANELESS unit?** `cc-where` handles exactly one kind of paneless unit (`offbox` cloud) and reports its state as UNKNOWN. **Every other tool: none.** Not one of the fourteen can name a workflow agent, an unnamed subagent, or a `--bg` worker.

**`cc-do --list`, rendered verbatim (the operator's runnable surface, for completeness of the inventory):**

```
cc-do — 13 runnable · 155 judgment
  RUN  1. deploy-live            [live layer 11 behind origin/main]
         bash ~/.claude/scripts/deploy-live.sh
  RUN  2. 13-mailbox-gc-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/13-mailbox-gc-activate.sh
  RUN  3. 18-fleet-activate      [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/18-fleet-activate.sh
  RUN  4. 27-worktree-gc-infra-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/27-worktree-gc-infra-activate.sh
  RUN  5. 30-teammate-reap-alarm-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/30-teammate-reap-alarm-activate.sh
  RUN  6. 33-escalation-watch-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/33-escalation-watch-activate.sh
  RUN  7. 34-deploy-plist-fallback-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/34-deploy-plist-fallback-activate.sh
  RUN  8. 35-auth-timeseries-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/35-auth-timeseries-activate.sh
  RUN  9. 36-start-latency-router-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/36-start-latency-router-activate.sh
  RUN  10. 37-postland-band-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/37-postland-band-activate.sh
  RUN  11. 38-accounts-board-activate [activation]
         CONFIRM=1 bash ~/.claude/autonomy/pending-activation/38-accounts-board-activate.sh
  RUN  12. 22-nightly-regression-activate [activation]
         bash ~/.claude/autonomy/pending-activation/22-nightly-regression-activate.sh
```

### 3b. 🚨 The census we do NOT own and should: CC's `sessions/<pid>.json` — and its measured limits

The landed doc's **L7** recommends adopting it, saying it is "PID-keyed, self-GC'ing … and unlike `cc-where` it already sees paneless workers". **All three halves are qualified by measurement.**

```
$ ps -axo pid=,ppid=,command= > /tmp/o6-ps3.txt      # redirect first — a Bash tool call is one zsh -c
$ python3  # argv[0] ends /claude or claude.exe ; registry = glob ~/.claude*/sessions/*.json
LIVE claude session-shaped procs: 18 | REGISTRY rows: 11
covered: 10 / 18
```

| Finding | Number | Note |
|---|---|---|
| live claude session-shaped processes | **18** | 16 × `node_modules/.bin/claude` + 2 × `claude.exe --agent-id` |
| CC-native registry rows (4 config dirs, deduped on pid) | **11** | 15 files; `.claude` and `.claude-next` are the same dir via symlink |
| **coverage** | **10 / 18 = 56%** | — |
| **named teammates covered** | **0 / 2** | `--agent-id A10-hostile-reviewer@session-84bde2e9` (pid 17602) and `--agent-id effort-survey@session-17d66411` (pid 81402) are in **neither** the files **nor** `claude agents --json` |
| stale rows | **1** | pid 1378 `voiceink-6b status=idle procStart=Fri Aug 14` — no live proc. Self-GC is real but not complete (a probe session's row *did* vanish between two reads 6 min apart) |
| uncovered interactive sessions | **6** | 3 driven by an `expect` harness (relogin/limit-recover), 3 plain `--effort xhigh`. All in globbed config dirs (`CLAUDE_CONFIG_DIR` read per-pid from `ps -axwwEo`), so this is **not** a glob artefact. **Cause unmeasured** — see §6 |

**`claude agents --json` is the same store, filtered, and it is the single best oversight primitive we are not using.** MEASURED — run once per config dir, no TTY needed:

```
$ CLAUDE_CONFIG_DIR=~/.claude-tertiary ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe agents --json
[ { "pid":43029, "cwd":"…/chris-resume", "kind":"interactive", "startedAt":…,
    "sessionId":"9d874911-…", "name":"chris-resume-66", "status":"busy" }, … ]
```

Totals: `.claude` 2 · `.claude-secondary` 2 · `.claude-tertiary` 3 · `.claude-quaternary` 3 = **10 rows**. It filters the stale row (good) and still misses both teammates (bad).

**One caveat that matters for SEE.** The `status` in the JSON view and the `status` in the file **disagree for the same pid at nearly the same instant**: pid 60323 reads `"shell"` on disk and `"busy"` in `--json`; so do 61532, 20435, 53709. The JSON view coarsens *running-a-bash-command* into *busy*. If we adopt this as the census, adopt the **file's** status, not the view's.

---

## 4. THE SEVEN GATES — corrected to NINE, with file:line, purpose, and per-unit firing

The landed doc says "a Workflow agent passes through 0 of our 7 Agent-tool gates". The count is low. Both `Agent` PreToolUse hooks are registered identically in all four config dirs (`settings.json` `PreToolUse` `matcher:"Agent"` → `agent-teams-enforce.sh`, then `frontier-spawn-gate.sh`), and `agent-teams-enforce.sh` contains **8** `permissionDecision:"deny"` sites, not 6:

```
$ grep -n 'permissionDecision": *"deny"\|permissionDecision: *"deny"' hooks/agent-teams-enforce.sh
119: 219: 416: 428: 481: 532: 571: 655:
```

| # | Gate | file:line (deny site) | What it is FOR | U1 plain subagent | U2 named teammate | U3 workflow agent | U4 pane session | U5 `--bg` | U6 `-p` | U7 cloud |
|---|---|---|---|---|---|---|---|---|---|---|
| **G1** | **duplicate-worker lease** | `hooks/agent-teams-enforce.sh:113` call → `:119` deny | stops a session that does NOT hold the item lease from *spending the fleet* — the recursion that reached 224 spawns / 91 sessions in 38 min | ✔ | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |
| **G2** | **machine capacity** `cc_capacity_admit agent-tool` (`CC_ADMIT_LOAD_TERM=off`; terms `headroom,segments,active`, ACTIVE ceiling 8) | `:215` call → `:219` deny | keeps the box off the compressor-panic edge and reserves slots for the operator at the keyboard | ✔ | ✔ | ✘ | ✘ (has its OWN gate, `handoff-fire.sh:6354` `capacity_gate`) | ✘ | ✘ | ✘ |
| **G3** | **spawn depth** `CC_SPAWN_MAX_DEPTH` | `:411` test → `:416` deny | a subagent spawning a subagent is the ignition path for the watchdog panics | ✔ | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |
| **G4** | **per-session spawn budget** `CC_SPAWN_MAX_PER_SESSION` | `:423` test → `:428` deny | bounds one session's whole fan-out tree; charges **attempts**, not admissions | ✔ | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |
| **G5** | **spawn lineage generation** `CC_LINEAGE_MAX_GEN` (default 3) | `:476` call → `:481` deny | bounds the ladder desk → wave lead → phase session → teammates; the counter that does NOT reset at a session boundary | n/a | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |
| **G6** | **teammate model allowlist** (SSOT `model-config.yaml .auto_mode_allowlist.non_firstParty_max`) | `:509` read → `:532` deny | an off-allowlist model silently demotes to acceptEdits and breaks team parallelism | n/a | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |
| **G7** | **brief-length cap** (WARN 150 / **DENY 250** lines) | `:562` guard → `:571` deny | an oversized brief burns the teammate's context and drives the GH #49593 `/compact` crash → wave stall | n/a | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |
| **G8** | **background-subagent implementation block** (`RUN_BG=true && IMPL_COUNT ≥ 2`) | `:648` test → `:655` deny | code-writing must go through Agent Teams, for visibility and coordination | ✔ | n/a | ✘ | ✘ | ✘ | ✘ | ✘ |
| **G9** | **frontier spawn cap** (`frontier_discovery_budget.max_fable_spawns_per_session`) | `hooks/frontier-spawn-gate.sh` whole file, 67 lines; refusal at `:59` | bounds autonomous escalation to the frontier tier per session | ✔ | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |

**Two advisory arms sit on the same hook and also miss U3** (they `allow` + `additionalContext`, so they shape rather than refuse): the **delivery-contract negation guard** (`:593-618` — a brief that suppresses writes but names no absolute delivery path; 4 of 5 agents lost their reports to this on 2026-08-05) and the **brief-over-WARN nudge** (`:579`).

**Why U3 fires none of them** — MEASURED by A5, not re-derived here: 9 workflow agents minted 11:43:46–49Z produced **0** `agent-tool` rows in `idl.jsonl` in that window while the same ledger took **874** other rows. The `Agent` PreToolUse matcher never fires for `agent()`.

**Read the table as a governance statement:** the nine gates encode nine *different* lessons, each bought with an incident — a duplicate worker, a kernel panic, a 91-session cascade, a wave stall, a silent auto-mode demotion, five stranded reports. **Changing orchestration unit from `Agent({name})` to `agent()` discards all nine at once, silently, with no log entry anywhere.** That is not a capacity property; it is the exact shape of "things blindly going on by themselves".

---

## 5. AUDIT, TESTED — can the operator reconstruct a workflow agent tomorrow?

**The test.** Pick a completed agent from a past run, on disk only, and reconstruct what it did and why. Subject: `wf_477e043f-09b`, 2026-08-16, six agents, in `.claude-tertiary`.

### 5a. Finding it — four coordinates, no index

To reach the run I had to already know: **(1)** which of 4 account stores · **(2)** the project slug (`-Users-chrisren-Development--worktrees-wt-pool-8`) · **(3)** the parent session uuid (`f9d4b4ee-…`) · **(4)** the `wf_` id. There is **no index** anywhere — not in `~/.claude/autonomy/`, not in `logs/`, not in the backlog. The census that finds them at all is a filesystem walk:

```
$ for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
    find "$d/projects" -type d -name 'wf_*' | wc -l
    find "$d/projects" -path '*/subagents/*' -name 'agent-*.jsonl' | wc -l
  done
→ 160 workflow run dirs · 3,409 agent transcripts across 4 stores
```

Starting from *"an agent did something wrong yesterday"* with no other information, the only entry point is a 3,409-file grep.

### 5b. What the run's own metadata records — and what it omits

```
$ cat wf_477e043f-09b/agent-a50bd9ff405ff51c8.meta.json
{"agentType":"workflow-subagent","spawnDepth":1}          ← 48 bytes. no timestamp, no prompt, no parent, no name
$ head -1 wf_477e043f-09b/journal.jsonl
{"type":"started","key":"v2:8aa77b5a…","agentId":"a38893d03b1ce18be"}   ← key is a HASH. no timestamp. no prompt.
```

The journal holds two row types only: `started` and `result`. **Row-type census for this run: `{'started': 6, 'result': 3}`.**

### 5c. The reconstruction, per agent

```
agent-a38893d03b1ce18be  332 KB  {'user':48,'attachment':2,'assistant':68}  Bash×46  21:40:11 → 21:55:30
agent-ae2cbb5dca992b73f  406 KB  {'user':61,'attachment':2,'assistant':96}  Bash×58  21:40:12 → 22:03:22
agent-a5785f155e8462e69  283 KB  {'user':44,'attachment':2,'assistant':62}  Bash×42  21:40:26 → 22:03:17
agent-a8ce02bfc0e62ea81  464 KB  {'user':73,'attachment':2,'assistant':109} Bash×70  22:03:22 → 22:31:19
agent-acc9ddf75911d4c43  324 KB  {'user':46,'attachment':2,'assistant':67}  Bash×44  22:06:17 → 22:23:14
agent-a50bd9ff405ff51c8   50 KB  {'user':2, 'attachment':2}                 —        22:03:17 → 22:06:17
```

**Result: 6 started · 5 did work · 3 recorded a result.** Three independent audit defects fall out:

1. **The journal under-records outcomes by half.** `a5785f155e8462e69` (42 bash calls) and `ae2cbb5dca992b73f` (58 bash calls) both worked for ~23 minutes and appear in the journal **only as `started`**. An operator reading `journal.jsonl` would conclude two agents never finished; they did, and their work is only in their transcripts.
2. **One agent is a silent void.** `a50bd9ff405ff51c8` has **zero assistant turns and zero tool calls** across a 3-minute span, and no `result` row. There is nothing on disk that says whether it was queued-and-cancelled, errored, or refused. The binary carries the string *"The workflow stopped before this agent finished."* — which is a message, not a record.
3. **The transcript itself is excellent — when you find it.** Full fidelity: the brief verbatim (`Repo: reso-management-app at …  READ-ONLY — do not edit anything. GOAL WE ARE DESIGNING FOR: add an undo affordance to the per-guest-row delete …`), all 42 bash commands with timestamps (`git fetch origin main -q…`, `git show origin/main:src/app/actions/replicache/operationBuilder.ts > /tmp/ob.ts…`), and the returned summary.

### 5d. Verdict on AUDIT

**Reconstructing a workflow agent is POSSIBLE and EXPENSIVE.** Rated against the four coordinates: the *content* is complete, the *index* does not exist, the *outcome ledger* is wrong 3-of-6, and *cross-referencing to our own logs is impossible* because every one of those 42 bash commands was written to `bash-commands.log` under the parent's session uuid. **AUDIT is not a NONE cell — it is a cell that will pass any structural check and fail the only question that matters: "which agent did this, and why?"**

---

## 6. WHAT I COULD NOT MEASURE, AND WHY

| # | Unmeasured | Why | The probe that settles it |
|---|---|---|---|
| **U-1** | The `--bg` row of every column, first-hand | **Zero `--bg` workers were alive** in my window (`grep -cE 'bg-pty-host\|daemon run\|bg-spare'` → 1, and that one is the spare). Starting one would violate read-only *and* the evictor holds it 1 h | one `claude --bg` under `CLAUDE_CONFIG_DIR=<copy>` with cwd = a scratch repo, then `claude agents --json --all`, then `cc-where`, then teardown by pid |
| **U-2** | The operator's background-session view (`1 awaiting input · 0 working · 3 completed`) live | same — nothing to render. The strings `awaiting input` are in the binary at 3 offsets, so the surface EXISTS | same as U-1, then screenshot |
| **U-3** | Whether `/workflows` can stop a workflow *from another pane* | I did not run it (it is a TUI slash command in the parent session; running it would key a live pane) | operator runs `/workflows` in a pane holding a live workflow and reports whether the list is session-scoped or global |
| **U-4** | **Why CC's registry misses 8 of 18 sessions** | The 6 missing interactive ones are in globbed config dirs (verified per-pid via `ps -axwwEo … CLAUDE_CONFIG_DIR=`), same binary path, mixed launch shapes (3 via `expect`, 3 via `cc-close-attrib`) — and 2 of the covered ones have the *same* `cc-close-attrib` parent. No discriminator found | `fs_usage -w -f filesys \| grep 'sessions/'` across one cold start of each shape; or diff the env of a covered vs uncovered pid |
| **U-5** | Whether `waitingFor` actually appears under a live permission prompt | no session was waiting during my snapshot; the value domain is read from the binary, not observed | park a session on a permission prompt in a copied config dir and read its `sessions/<pid>.json` |
| **U-6** | Whether Esc in the parent pane aborts a running Workflow's in-flight agents | the abort machinery is present (`canInterruptTurn`, `workflow-abort`, `Dynamic workflow cancelled`) but I did not execute it | run a 3-agent workflow in a scratch session, press Esc mid-run, and check the run dir for `started` rows with no `result` |
| **U-7** | `cc-panes` — whether it was ever built and lost, or never built | `git log --all --diff-filter=A -- 'bin/cc-panes*'` is **empty**, so it is not in the graveyard either | ask whether task #145's "completed" refers to `cc-where` under a different name |

---

## 7. THE DESIGN CONSTRAINT THIS AXIS IMPOSES

**The minimum set of non-NONE cells before a unit class may carry work the operator wants oversight on.** Not four — that would ban every cheap unit and re-answer the capacity question wrongly. Three, and one of them is the one we always skip.

> **A unit class is fit to carry overseen work iff it has (S) a state readable from ONE place without going to look, (T) a stop that names it individually from that same place, and (A) a record that says which unit did it. INTERRUPT may be inherited from a parent that is itself overseen; the other three may not.**

Stated as the test each cell must pass:

| | Requirement | Why this is the floor | Who fails it today |
|---|---|---|---|
| **S** | The unit appears in **one census** the operator runs in one command, with a live state, without opening its window | 15 windows is already past what a human scans; 30 is not a scanning problem, it is a *reading* problem. A census that requires N looks does not scale past N | unnamed subagent · workflow agent · headless · (cloud: named but `state=UNKNOWN`) |
| **T** | The unit has a **name in a namespace the operator can type**, and one command that stops **that one unit** | STOP is what separates oversight from spectating. `cc-teardown` proves the shape and proves the limit: it refuses an agent name outright (`bin/cc-teardown:194`), so the namespace — not the willingness — is the binding constraint | unnamed subagent (by-construction) · workflow agent (product-only, TUI-only) · `--bg` (ours: none) · headless (`kill` is not a rail) |
| **A** | Every action the unit takes carries **its own id**, not its parent's, in whatever log we keep | without this, a post-mortem cannot assign an action to an actor, and every incident becomes "one of sixteen agents did this" | unnamed subagent · workflow agent — both write into the lead's sid (516 rows / one uuid, MEASURED) |
| **I** | *(inheritable)* the unit either surfaces its own `waitingFor`, **or** blocks a parent that does | this is the one that is genuinely fine for in-process units: they cannot silently wait, because they hold the parent's turn | `--bg` (arms a pane-addressed wake with no pane — 3/3) · headless (by-construction) |

**Three consequences that follow directly, and are the load-bearing output of this axis:**

1. **Do not add a second census. Adopt `claude agents --json` and extend it.** It already answers S for pane sessions and (upstream) for `--bg`, across all four accounts, without a TTY. Its two measured defects are narrow and nameable: it misses `--agent-id` teammates (0/2) and its status is coarser than the file it reads. Building a 15th tool beside it is exactly the failure mode this repo names `inventory-before-building`.
2. **The gate that matters is not a cap, it is a NAMESPACE.** Every empty STOP cell traces to the same missing thing: an id the operator can type. `cc-teardown` is not too weak — it is correctly refusing to act on an address it cannot verify. Fixing STOP for workflow agents means giving a run and its agents a typeable address **first**; the stop command is trivial after that.
3. **G1–G9 must be re-sited off the `Agent` tool, or fan-out becomes a governance bypass by construction.** Nine gates, nine incidents, all of them discarded by choosing a different orchestration verb, with no ledger row to notice. Whether the correct fix is a matcher edit or a new chokepoint is A5's open L8 and is *not* settled here — but the design constraint is: **no unit class may be the recommended fan-out primitive while it fires zero admission gates.** That is the operator's sentence — *"without things blindly going on by themselves"* — restated as an invariant.
