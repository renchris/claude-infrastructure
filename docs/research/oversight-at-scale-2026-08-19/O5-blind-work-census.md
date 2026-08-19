# O5 — How much work is already running blind?

**Census taken 2026-08-19 13:18–13:35 UTC, live, read-only.** Box: MacBookPro18,2 M1 Max, 10 cores,
64 GiB, Claude Code 2.1.220 across 4 account config dirs. Nothing was killed, stopped, torn down or
reconfigured; every command below is a read.

---

## 1. Verdict (≤5 lines)

**The fear is already realised, and the blind unit is the ORDINARY PANE SESSION, not the exotic one.**
18 Claude agent processes are live; the operator's own census tool (`cc-where`) shows **12**, Claude
Code's own registry holds **11**, and only the memory alarm — which knows nothing about what a session
is *doing* — counts all 18. **Every one of those 18 runs `--permission-mode auto` with
`Bash(scripts/ship-land.sh:*)` on the allow-list, so any of them can land code on `origin/main`
without a prompt** — and 75 commits did land in the last 24 h, 21 of them between 00:00 and 07:00,
all authored "Chris Ren", 74 of 75 carrying no agent trailer at all.
The gap is not STOP — `cc-teardown`, `cc-reaper` and launchd reach anything with a pane or a pid. It is
**SEE** (three instruments, three totals, none complete), **AUDIT** (283 workflow agents fleet-wide
started and never recorded a result), and an **INTERRUPT** that is built, wired into 8 callers, and
inert for want of two environment variables.

---

## 2. The numbers, with the command behind each cell

### 2.1 Live agent census — three instruments, three answers

| Instrument | Count | Command | Verdict |
|---|---|---|---|
| `ps` (ground truth) | **18** agents (16 pane sessions + 2 `--agent-id` teammates) | `ps -Aww -o pid=,ppid=,etime=,rss=,args= > /tmp/o5-ps1.txt; LC_ALL=C /usr/bin/grep -aF 'claude-220/node_modules' /tmp/o5-ps1.txt` | MEASURED |
| CC's own registry `sessions/<pid>.json` | **11** rows | `ls ~/.claude*/sessions/*.json` (4 roots; `.claude-next/sessions` is a symlink to `.claude/sessions`) | MEASURED — **8 of 18 live agents (44%) have no row** |
| our `cc-where` | **12 panes** | `~/.claude/bin/cc-where` | MEASURED — **6 of 18 live agents (33%) invisible** |
| `capacity-alarm.jsonl` | **18** (`sessions:18`) | `tail -2 ~/.claude/logs/capacity-alarm.jsonl` | MEASURED — the only complete count, and it alarms on **memory headroom**, never on autonomy |

The 8 agents with **no registry row**: `9576 17602 21808 21952 29540 55717 56705 81402`
(`comm -23 <sorted live pids> <sorted registry pids>`). Two are teammates (expected — different
entrypoint); **six are ordinary pane sessions.**

**The registry also carries a PID-reuse collision.** Row `~/.claude/sessions/1378.json` claims
`{"status":"idle","cwd":"/Users/chrisren/Development/voiceink","name":"voiceink-6b"}`; `ps -p 1378 -o
comm=` returns **`postgres: walwriter`**. MEASURED. A consumer that trusts the registry's pid would
address a PostgreSQL worker as a Claude session.

**And its `status` field goes stale without saying so.** `statusUpdatedAt` age at census:
`43029` = `busy`, **3058 min (51 h) old**, while that session's transcript was last written 1.1 h ago;
`1378` = `idle`, 7808 min old, pid recycled. Command:
`python3 -c "…json.load(open(f)); (now-statusUpdatedAt)/60000"` over all four `sessions/` dirs.
EXISTS is reliable in that registry; **STATE is not**.

### 2.2 Sessions with no human input

`hrs_since_human` = age of the newest `type:"user"` transcript entry that is not a `tool_result` and
not a system-reminder (`/tmp/o5-lastinput.py`, transcript walk over all four `projects/` roots).

| Bucket | Count | Detail |
|---|---|---|
| No user turn in **> 4 h** | **1** | `29540` (chris-capital-group-contributions) — **31.1 h**, still resident, `--effort max --resume` |
| No user turn in **> 1 h** | **4** | `21952`, `43029`, `53709`, `60323` — all 1.2 h |
| **Never produced a transcript at all** | **3** | `9576` (wt-pool-7), `55717` (wt-cc-043659-7938), `56705` (wt-cc-043659-8018) — alive 1 h 45 m, 400–430 MB each, **zero jsonl in any of the four config roots** |

The three silent ones are the sharpest case. `wt-pool-7` has a `.last-session-id` written
`Aug 19 04:37:04` naming `59061aac-…`, and **no `59061aac-….jsonl` exists anywhere**
(`for w in wt-pool-7 wt-cc-043659-7938 wt-cc-043659-8018; do … [ -f "$r/projects/…/$sid.jsonl" ]`).
`wt-cc-043659-7938` and `-8018` have no `.last-session-id` in any root either. Their task dirs
(`~/.claude/tasks/wt-cc-043659-*`) were created 04:37–04:38 and are **empty**. So: three sessions
fired ~1 h 45 m ago that have never completed a turn, and nothing on this box says so.

### 2.3 Workflow / in-process agents — the paneless population

`find ~/.claude*/projects -maxdepth 5 -type d -name 'wf_*'` → **160 run dirs**.
Journal parse (`journal.jsonl`, counting `type:"started"` vs `type:"result"`):

| Measure | Value |
|---|---|
| Fleet totals across 160 runs | **2,716 started · 2,433 results · 2,705 agent transcript files** |
| Runs where `started > result` (any age) | **39 runs, 283 agents that started and never recorded a result** |
| **In flight right now** (`started>result`, dir touched <24 h) | **4 runs, 35 agents started, 28 without a result** |

The four in-flight runs:

```
agents=23 started=23 results=15 age=0.04h  wt-pool-2   / 020aafc9 / wf_142784b1-c8b
agents=13 started=13 results=12 age=18.0h  claude-infra/ bde77ada / wf_96a89c2d-c5b   <- 18 h stale, abandoned
agents= 6 started= 6 results= 0 age=0.12h  claude-infra/ f285654f / wf_4385fe24-845
agents= 6 started= 6 results= 1 age=0.20h  claude-infra/ f285654f / wf_586b146f-72e
```

None of these 35 has a pane, a registry row, a mailbox, or a `cc-teardown` handle. The 18-hour-stale
run is a *finished-looking* run with one agent that never returned, and nothing surfaced it.

### 2.4 The 39-percentage-point precedent — found, and it was NOT overseen

```
/Users/chrisren/.claude-tertiary/projects/-Users-chrisren-Development-doc-classifier/
  1a705246-7ca4-4af1-b2fe-b7c0b8c29ab0/subagents/workflows/wf_0f8a38e6-82f
```

| Fact | Value | Command |
|---|---|---|
| Agents | **229** | `ls "$D"/agent-*.jsonl \| wc -l` → 229 |
| Journal | **229 `started` · 196 `result`** → **33 agents never returned** | `awk -F'"type":"' … journal.jsonl \| sort \| uniq -c` |
| Wall clock | **Jul 21 01:49 → 09:01 = 7 h 12 m** | `ls -lt "$D"/agent-*.jsonl` first/last |
| Journal event vocabulary | **exactly two types: `started`, `result`** | same command — there is **no `error`, no `failed`, no `cancelled`** |
| Live cost meter | **none** | journal carries no per-agent cost/usage event; the only spend surface is `claude-accounts`, which is **PULL** (the operator must run it) |

Answers to the three questions asked of this run:
- **Was it overseen?** No. It ran in a session's `subagents/workflows/` directory with no pane, no
  registry row and no operator-facing surface. The only artefact is the run dir itself, discovered
  here by a filesystem walk.
- **Could the operator have watched cost accrue in real time?** No. Nothing emits a running total.
  `claude-accounts` reports per-account 5 h / weekly meters on demand; no daemon pages on meter burn.
  `capacity-alarm` (every 60 s) pages on **memory**, not spend.
- **Is there ANY live spend meter a running wave surfaces?** **No.** MEASURED negative, positive-
  controlled: `capacity-alarm.jsonl`'s schema is memory-only
  (`headroom_gb, compressor_gb, active_gb, wired_gb, swap_used_mb, seg_pct, coal_procs`), and the
  workflow journal has two event types, neither carrying usage.
- **Because a failed agent and a lost agent produce the same absence, 33 of 229 is not even an error
  count** — it is the count of rows that never appeared.

### 2.5 Write / land / delete / spend authority — every actor named

**(a) The 18 sessions themselves — the largest authority on the box.**

| Fact | Value | Command |
|---|---|---|
| Sessions running `--permission-mode auto` | **all of them** (31 argv matches incl. wrappers) | `LC_ALL=C /usr/bin/grep -c 'permission-mode auto' /tmp/o5-cc.txt` |
| Fleet default mode | `"defaultMode": "auto"` | `python3 -c "json.load(open('~/.claude/settings.json'))['permissions']"` |
| Permission rules | **339 allow · 41 deny · 6 ask** | same |
| `git push` | in **ask** | `p['ask']` → `Bash(git push:*)`, `Bash(git reset --hard:*)`, `Bash(git restore:*)`, `Bash(git stash drop/clear:*)`, `Bash(fly deploy:*)` |
| **`scripts/ship-land.sh`** | in **allow** | `p['allow']` → `Bash(scripts/ship-land.sh:*)` |
| PermissionRequest hooks | 4, **all notify-only** (`notify.sh permission/question/plan`, `cc-permission-beacon.sh write`) — none auto-approves | `d['hooks']['PermissionRequest']` |

So the guard is real and deliberate — a bare `git push` prompts, `sudo`/`rm -rf /`/`git clean` are
denied — but **the sanctioned landing rail is ungated by design**, which is exactly the
claude-infrastructure standing-land authorization. That is DESIGNED autonomy with a named guard
(land-lock + gates + content-verify inside `ship-land.sh`). It is also, unambiguously, code reaching
trunk with no human in the loop.

**(b) Landing volume, measured on trunk.**

| Measure | Value | Command |
|---|---|---|
| Commits on `origin/main`, last 24 h | **75** | `git log origin/main --since='24 hours ago' \| wc -l` |
| …of those, landed 00:00–07:00 | **21 (28%)** | `git log … --pretty='%ad' --date=format:'%H' \| sort \| uniq -c` |
| Commits on `origin/main`, last 7 d | **509** | `git log origin/main --since='7 days ago' --oneline \| wc -l` |
| Distinct authors | **1 — `Chris Ren <ren.chris@outlook.com>`, 75/75** | `git log … --pretty='%an <%ae>' \| sort \| uniq -c` |
| Commits carrying any agent/session trailer | **1 of 75** | per-commit `git show -s --format='%B' \| grep -iE 'Co-Authored-By: Claude\|Session-Id\|Agent-Id\|Generated with'` |

**(c) launchd actors — 31 jobs, 28 of them ours.** Enumerated with
`for f in ~/Library/LaunchAgents/com.{claude,chrisren}.*.plist; do PlistBuddy -c 'Print
:ProgramArguments' …; launchctl list | awk '$3==LABEL'`. Authority column from
`grep -nE '^[^#]*(cc-teardown|git worktree remove|rm -rf|handoff-fire\.sh|claude -p|ship-land)'`
against each script.

| Job | Every | Authority | Guard | Who would know if it misbehaved |
|---|---|---|---|---|
| `com.chrisren.autonomy-sweep` | 300 s | **fires sessions** (`handoff-fire` ×2), **tears down** (`cc-teardown` ×4), `CC_FIRE_CLOUD=on` → **fires cloud sessions that spend quota** | sweep gates + teardown refusal codes | last exit **-15 (SIGTERM)**; nothing pages on daemon exit code |
| `com.chrisren.cc-reaper` | 300 s | **kills sessions** (`cc-teardown` ×16), `rm -rf` ×4, `git worktree remove`, `claude -p` | teardown gate returns 10=DEFER / 2=REFUSE / 5=FAIL and is trusted; land-path whitelist protects `ship-land` | `~/.claude/logs/cc-reaper.log` — pull only |
| `com.claude.dispatcher` | 300 s | **fires sessions** into `claude-infrastructure` | dispatch gates | `dispatch-fires.log` = **694 entries today**, 24,712 total — pull only |
| `com.claude.postland-verify` | 300 s | runs the full suite, `rm -rf` ×9, `kill -TERM` ×2, touches the land path | background-QoS'd (`taskpolicy`) | log only |
| `com.claude.deploy-live` | 600 s | **converges the LIVE `~/.claude` layer from trunk** — a landed commit becomes executing code within ~10 min, unattended | ff-only + deploy gate | log only |
| `com.claude.cc-gc` | 6 h | `rm -rf` (`--apply`) | GC policy | log only |
| `com.claude.worktree-gc-infra` | on demand | `rm -rf` ×2 (worktrees) | GC policy | log only |
| `com.claude.devserver-gc` | on demand | kills dev servers | `DEVGC_ACT=1` | log only |
| `com.claude.compressor-sentinel` | KeepAlive | **`CC_SENTINEL_ACT=stop` — SIGSTOPs processes** | compressor-segment thresholds | log only |
| `com.claude.lead-supervisor` | KeepAlive | `handoff-fire.sh`, `cc-teardown` | supervisor rules | last exit **-15** |
| `com.claude.boot-resume` | 300 s | relaunches sessions after reboot | — | log only |
| `com.claude.relogin` | 1 h | touches **auth** (`cc-relogin-poll --once`) | — | log only |
| `com.claude.discovery` | 1 h | **mints backlog items**, `rm -rf` ×1 | discovery critic | log only |
| `com.claude.capacity-alarm` | 60 s | read-only alarm | — | last exit **2** |
| `com.claude.auth-timeseries` | 300 s | read-only sampler | — | last exit **126** (not executable / permission denied) — **failing, unnoticed** |
| `com.claude.qos-census` | 600 s | read-only | — | last exit **3** |
| `com.claude.accounts-keepwarm` · `browser-spin-guard` · `caffeinate-floor` · `log-rotation` · `power-policy-verify` · `session-search-{sweep,backfill}` · `teammate-reap-alarm` · `restic-claude-archive` · `verify-2114-archive` · `watch-claude-code-2118-hold` · `screenshot-clipboard` | various | read/maintenance | — | log only |
| `com.claude.desk-invariant` · `com.claude.nightly-regression` · `com.claude.team-orphan-reaper` | — | **NOT LOADED** | — | nobody — a disabled guard looks identical to a passing one |

**Four launchd jobs are reporting a non-zero last exit right now** (`auth-timeseries` 126,
`capacity-alarm` 2, `qos-census` 3, `watch-claude-code-2118-hold` 1) and **two were SIGTERM'd**
(`lead-supervisor` -15, `autonomy-sweep` -15). `launchctl list` is the only place that says so, and
nothing reads it on a schedule.

**(d) Off-box.** `cc-where` reports **84 cloud sessions, every one `state=UNKNOWN`**
(`cc-where | grep -c 'kind=offbox'` → 84; `grep -c 'state=UNKNOWN'` → 84). The tool is honest — it
prints `OFF-BOX — no screen anywhere; these run in an Anthropic VM` and offers only
`open https://claude.ai/code/<id>`. These are fed by `autonomy-sweep` with `CC_FIRE_CLOUD=on`.

### 2.6 The four oversight verbs, scored per unit class

| Unit class | Live now | SEE | INTERRUPT | STOP | AUDIT |
|---|---|---|---|---|---|
| Pane session **with** a registry row + a kitty pane | 10 | ✅ `cc-where`, kitty tab | ✅ `notify.sh` (local) | ✅ pane, `cc-teardown`, `cc-reaper` | ⚠️ transcript yes; commit attribution **no** |
| Pane session with **no** registry row | 6 | ❌ absent from `cc-where` **and** the registry | ⚠️ only if it fires a hook | ✅ SIGTERM by pid (if you find the pid) | ⚠️ transcript only if it wrote one — 3 wrote none |
| `--agent-id` teammate | 2 | ⚠️ has a kitty pane via `cc-pane-runner`, but **no registry row** | ✅ pane | ✅ `shutdown_request` / pane close | ✅ own transcript |
| Workflow `agent()` in-process | 35 started / 28 unreturned | ❌ nothing but a filesystem walk | ❌ none | ❌ **no abort path in anything we own** | ⚠️ per-agent jsonl exists; the journal cannot say *failed* |
| launchd daemon | 28 loaded | ⚠️ `launchctl list` only | ❌ none (logs are pull) | ✅ `launchctl bootout` | ⚠️ per-daemon log, no index |
| Cloud `--cloud` session | 84 | ⚠️ listed, `state=UNKNOWN` | ❌ none | ❌ none from here | ❌ none from here |

### 2.7 Accumulated blind residue

| Measure | Value | Command |
|---|---|---|
| Branches ahead of `origin/main` | **1,731** | `git for-each-ref refs/heads \| while read b; do git rev-list --count origin/main..$b; done` |
| Worktrees | **88** | `git worktree list \| wc -l` |
| Unread event records on disk | **685** (`cc-teardown` 149 · `watchdog` 504 · `handoff-alarms` 32) | `ls ~/.claude/{cc-teardown,watchdog,handoff-alarms} \| wc -l` |
| Dispatcher fire-log lines today | **694** (24,712 all-time) | `grep -c '2026-08-19' ~/.claude/logs/dispatch-fires.log` |

### 2.8 The INTERRUPT channel that leaves the desk is BUILT, WIRED — and INERT

`hooks/notify.sh` delivers locally via **`osascript`** (macOS Notification Center) and **`afplay`**
(sound). A phone channel also exists and is not a stub:

| Fact | Value | Command |
|---|---|---|
| Push implementation | `scripts/push-send.sh` (Pushover), `hooks/push-critical.sh`, `hooks/curl-gate.py` | `LC_ALL=C /usr/bin/grep -rlE 'ntfy\|pushover\|Pushcut\|APNs\|web-push\|hooks\.slack\.com\|api\.telegram' hooks/ bin/ scripts/` |
| Wired into `settings.json` | **3 references** | `grep -c 'push-critical\|push-send' ~/.claude/settings.json` |
| Callers | `notify.sh`, `cc-notify`, `cc-inbox-guard`, `cc-digest`, `waiting-recycle.sh`, `autonomy-sweep.sh`, `desk-recycle-invariant.sh`, `delivery-verify.sh` | `grep -rln 'push-critical\|push-send' hooks/ bin/ scripts/ commands/` |
| Credentials required | `PUSHOVER_TOKEN` + `PUSHOVER_USER`; unset ⇒ **exit 3 INERT**, and the script says so in its own words: *"the phone channel is not wired (P0-7 operator step)"* | `push-send.sh:61-62` |
| Credentials present in `settings.json` `env` | **0 of 8 keys** | `python3 -c "…['env']"` |
| Credentials present in **any** live agent's environment | **0 across all 18** | `for p in $(cat /tmp/o5-agents.txt); do ps -Eww -p $p \| tr ' ' '\n' \| grep -c '^PUSHOVER'; done \| awk '{s+=$1} END{print s}'` |
| …positive control on that same read | **3** (`PATH`, `HOME`, `CLAUDE_CONFIG_DIR` all found) | same pipeline, pattern `^(PATH\|HOME\|CLAUDE_CONFIG_DIR)=` |
| Credentials in `~/.zshrc`, `~/.zprofile`, any LaunchAgent plist | **none** | `grep -rl 'PUSHOVER' ~/.zshrc ~/.zprofile ~/Library/LaunchAgents/*.plist` |

**So the operator's off-desk INTERRUPT is one environment variable pair away from working, and today
it is zero.** Eight callers page into it; every one of them returns INERT. 28% of the last 24 h of
landings happened between 00:00 and 07:00, into a channel that reaches nobody who is not sitting at
this Mac. This is the single cheapest oversight repair on the whole board — it is a credential, not
a design.

⚠️ **This paragraph originally asserted the opposite** ("no push channel exists"), from
`grep -rlE … ~/.claude/hooks/ ~/.claude/bin/ ~/.claude/scripts/` returning empty. That grep was
structurally blind: `~/.claude/*` is a per-file **symlink** layer and BSD `grep -r` does not follow
walk-met symlinks. Re-run against the real checkout it returns three files. Recorded here because it
is the same instrument defect as §3's `ps | grep` miss, in a different disguise — **a null from a
blind instrument is not absence.**

---

## 3. What I could NOT measure, and why

1. **Whether a "user turn" was typed by the operator or injected by `handoff-fire`.** Both arrive as
   `type:"user"` in the transcript with no provenance field. The 1.2 h figure for four sessions is
   almost certainly a fired brief, not a human — but I cannot prove it from the transcript, so §2.2
   is labelled *no user turn*, not *no human*. Fixing this needs a fire-stamp in the injected message.
2. **What the three silent sessions (9576, 55717, 56705) are actually doing.** Reading their state
   would need a pane capture or a keystroke, both of which the read-only rule forbids. All I can say
   is: alive 1 h 45 m, ~420 MB, zero transcript, empty task dir. Stuck-on-a-modal and
   thinking-very-hard are indistinguishable from outside.
3. **The 229-run's actual cost.** 39 pp of a weekly meter is QUOTED from the settled research; the run
   dir carries no usage event, so I could not re-derive it. What I *did* verify is the absence: the
   journal's entire event vocabulary is `started` and `result`.
4. **Whether `43029`'s 51-hour-old `busy` is a stale write or a legitimately unchanged state.** CC
   appears to stamp `statusUpdatedAt` on *change*; a session that never left `busy` would look
   identical to one whose writer died. Either way the consequence is the same and it is the one that
   matters: **row age is not a liveness signal.**
5. **Off-box session state.** Requires an authenticated claude.ai fetch per session; out of scope for a
   read-only local census, and `cc-where` already declares it `UNKNOWN`.

**Two instrument defects worth naming, because both bit this census and both produced a confident
false negative before being caught.**

**(i) The symlink layer.** `grep -r` over `~/.claude/hooks|bin|scripts` reported *no push channel
exists*. `~/.claude/*` is a per-file symlink layer and BSD `grep -r` does not follow walk-met
symlinks; the same grep over the real checkout returns `scripts/push-send.sh`,
`hooks/push-critical.sh`, `hooks/curl-gate.py`. The corrected finding (§2.8) is materially different
and materially more useful.

**(ii) The `ps | grep` pipeline.** My first three passes reported
**21** live CC processes; the true figure is **33** process rows / **18** agents. Cause: the Bash tool's
shell is zsh with a grep rewrite, and `ps … | grep -F` silently drops matches when argv contains the
embedded newlines of an inline fired prompt (the stream is treated as binary). The same data written
to a file and read with `LC_ALL=C /usr/bin/grep -a` returns 33. **A 35% undercount, from plumbing, in
the very session whose job was to count.** Every number above was re-derived through the file path.

---

## 4. DESIGNED autonomy vs ACCIDENTAL blindness

**DESIGNED — has a guard, someone chose it, leave it alone.**

- `--permission-mode auto` + `Bash(scripts/ship-land.sh:*)` allowed → the standing-land
  authorization in `.claude/CLAUDE.md`, guarded by land-lock, gates and content-verify.
- `cc-reaper` / `cc-teardown` killing sessions — guarded by refusal codes 10/2/5, land-path whitelist.
- `deploy-live` converging the live layer every 600 s — ff-only, gated.
- `cc-gc`, `worktree-gc-infra`, `devserver-gc` deleting — GC policy, bounded scope.
- `compressor-sentinel` SIGSTOPping — a panic-prevention guard with measured thresholds.
- `autonomy-sweep` / `dispatcher` firing sessions — the drain pipeline, deliberate.
- The `deny`/`ask` lists (`sudo`, `git clean`, `rm -rf /`, bare `git push`, `fly deploy`).

**ACCIDENTAL — no guard, nobody chose it. This is the actionable list.**

1. **Six pane sessions exist in no registry and in no `cc-where` output.** Not a policy, a gap.
   Nothing can page on them, reap them, or count them into routing.
2. **Three sessions have been alive 1 h 45 m with zero transcript and an empty task dir.** No watchdog
   fires on "started but never produced a turn".
3. **A registry row survives its process and is re-pointed at an unrelated PID** (`1378` → postgres).
   PID-keyed with no `procStart` re-check at read time.
4. **283 workflow agents fleet-wide started and never recorded a result**, 28 of them in flight today.
   The journal has no failure event, so this is unobservable as an error — only as an absence.
5. **An 18-hour-stale workflow run looks complete.** Nothing ages out or alarms on `started > result`.
6. **Four launchd jobs are exiting non-zero and two were SIGTERM'd, and nothing reads exit codes.**
   `auth-timeseries` has been returning 126 (not executable) with no alarm.
7. **Three guard jobs are NOT LOADED** (`desk-invariant`, `nightly-regression`, `team-orphan-reaper`)
   and an unloaded guard is indistinguishable from a passing one.
8. **Git history cannot separate agent work from operator work** — 75/75 authored "Chris Ren",
   74/75 with no trailer. AUDIT of "what did unit X land" is not reconstructable from the repo.
9. **The off-desk INTERRUPT channel is built, wired into 8 callers, and INERT for want of two
   environment variables** (`PUSHOVER_TOKEN`/`PUSHOVER_USER`, absent from settings.json, from all 18
   live agent environments, from the shell rc files and from every LaunchAgent plist). Away from the
   Mac, INTERRUPT is 0, while 28% of landings happen overnight. **This is the one item on this list
   that is an operator credential rather than an engineering task.**
10. **1,731 branches ahead of trunk / 88 worktrees / 685 unread event records** — the accumulated
    exhaust of work that ran and was never collected.

**The exposure, in the operator's terms.** *Right now*, **6 pane sessions + 28 unreturned workflow
agents + 84 cloud sessions = 118 units you cannot see from any single place**, against 12 you can.
*The worst thing any of them could do before anyone noticed*: **land a commit on `origin/main`
through the allow-listed `ship-land.sh`, which `deploy-live` then makes the executing `~/.claude`
layer within 10 minutes** — with no prompt, no notification that leaves the desk, and a git author
line that reads "Chris Ren". That has happened 75 times in the last 24 hours. Every one of those was
almost certainly wanted; **the point is that a bad one would look exactly the same.**

---

## 5. The design constraint this axis imposes

> **Any new unit class must enter ONE census that is complete by construction, and must be able to
> say "I started" and "I finished/failed" into a store the operator can read without knowing the unit
> exists.**

Three sub-constraints, each forced by a measurement above:

- **C1 — Census completeness beats census richness.** Three instruments disagree (18 / 12 / 11) and
  the only complete one is the memory alarm, which counts processes because *processes are what it
  can't miss*. Any oversight surface must be derived from a source that cannot omit a unit —
  process table or a write-on-spawn ledger — not from a source a unit must opt into. Adding a
  fourth partial view makes things worse, not better.
- **C2 — Absence must be an event.** 283 agents "started and never returned" is invisible because
  the journal has no failure vocabulary and no ager. A unit class with no way to emit *failed* buys
  its throughput by moving the failure into the operator's blind spot. Every unit needs a
  started-at, a heartbeat or a deadline, and a terminal event that includes `failed`.
- **C3 — Authority must be attributable, at the point where it lands.** The single highest-stakes
  authority on this box — `ship-land.sh` on the allow-list under `--permission-mode auto` — produces
  a commit indistinguishable from a human's. A trailer naming the session id and unit class on every
  agent-authored commit is the smallest change that makes AUDIT possible at all, and it costs
  nothing at any scale. Without it, "more than 15 overseen units" is arithmetically impossible: the
  record they leave already cannot tell you which unit did what.

A corollary that falls out of §2.8 and cuts against every "just add more units" answer:
**INTERRUPT is the verb that does not scale by adding surfaces.** `osascript` at 18 units is a
usable ping; at 118 it is noise, and it is *zero* the moment the operator walks away. Any design that
raises the unit count must raise the *selectivity* of the interrupt in the same diff — fewer, better
pages — or it will have traded SEE for INTERRUPT and called it progress.
