# A12 — SKEPTIC pass on `A12-upstream-features.md`

Wave: exhaustive-drive 2026-09-08. Read-only. Every number below was re-run by this pass unless
marked *inferred*. Binary text re-extracted from
`~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe` with the axis's own recipe
(`tr -c '[:print:]\n'` + `awk 'length>=30'`) into the scratchpad; offsets differ slightly from the
axis's by construction and are given as `@offset` into this pass's extract.

## Verdict in one paragraph

The axis's *binary* readings are sound — every code claim I re-read (`Vd>0&&qd>Vd`, `mode:"dontAsk"`,
`outcome:"cancelled"`, `mct(){return I("tengu_propose_goal",!1)}`, `sessionHooksRegistry.add(r,"Stop","",
{type:"prompt"…})`, the Stop payload schema with `background_tasks`/`session_crons`) is verbatim, and its
two corpus censuses reproduce exactly (cap warnings 4 files / 6 events; `"name":"ProposeGoal"` 0 files).
Its *repo and store* readings are what fail: **three of eight recommendations rest on a premise the repo
already refutes** — the project-layer settings already carry the allow rules R3 says are missing; the
SubagentStop registration R2 calls a "cheap win" is staged as `migrations/0014-*` behind C10 row
`296cc04bc3fd`, and the hook it would register is pinned by test to emit *nothing*, the opposite of the
`additionalContext` R2 prescribes; and the `background_tasks` field R5 offers as the D8 discriminator is
documented in `hooks/goal-inert-watch.sh:50-67` as a backgrounded-only view whose empty list proves
nothing. One recommendation (R7) restates a discipline CLAUDE.md already carries. The axis also searched
for a *Statsig* override in a *GrowthBook* client and concluded the flag was unobservable; the local cache
`~/.claude/.claude.json → cachedGrowthBookFeatures` is readable and answers the axis's own open question
#1 today: `tengu_propose_goal` is ABSENT (⇒ default `false`) in all four accounts.

---

## 1. Numbers re-checked

| claim | axis | this pass | holds |
|---|---|---|---|
| `ENABLE_STOP_REVIEW` in 2.1.219 / 220 / 260 | 0 / 0 / 0 | `LC_ALL=C /usr/bin/grep -a -c -F` ⇒ **0 / 0 / 0**; `STOP_REVIEW` also 0/0/0 | yes |
| positive control `CLAUDE_CODE_ENABLE_AWAY_SUMMARY` | 4 (260) | **4** in 260; 6 in 219 and 220 | yes |
| readers of `ENABLE_STOP_REVIEW` anywhere | "nothing reads it" (git log -S only) | `grep -rl` over the worktree + `find -L` over the live `~/.claude/{hooks,scripts,bin,commands,skills}` + `~/.zshrc` ⇒ only today's wave docs | yes (strengthened) |
| registered hooks | 105 hooks / 21 events / 100% `command` | **100** hooks / 21 events / 100% `command` in `~/.claude/settings.json` (mtime 2026-09-08 16:23 local — a live store; the axis's 105 is not reproducible now). Other accounts: **94 / 95 / 94 hooks, 20 events** | types yes; count no; "fleet-wide identical" **no** (see § 3) |
| `permissions.allow` = 339, only 5 judge-relevant rules | 339; `cat/git log/git status/jq/Read` | 339 in the *user* file, 6 relevant (axis missed `Bash(~/.claude/scripts/…)` ×2). **Project layer `.claude/settings.json` (35 rules) carries `Bash(cc-backlog:*)`, `Bash(bin/cc-backlog:*)`, `Bash(cc-decide:*)`, `Bash(scripts/wrap-ledger.sh:*)`, `Bash(bash scripts/wrap-ledger.sh:*)`.** Binary `Hm={userSettings,projectSettings,localSettings,…}` @11043434 is the merged rule-source set feeding `alwaysAllowRules` | **premise fails** |
| cap code `Vd=env??8; if(Vd>0&&qd>Vd)` | verbatim | `let Vd=a.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP??8;if(Vd>0&&qd>Vd)return i("tengu_stop_hook_block_count",{count:qd,…,hit_cap:!0,goal_active:zf}),yield kt(\`A hook blocked the turn from ending ${qd} consecutive times…\`)` @16480439 | yes |
| genuine cap hits, 30 d | 4 files / 6 events, all `9 consecutive` | 6,144 files (was 6,140; four new today). Raw string 38 files; `type:"system"` emissions **4 files / 6 events** (2026-08-10 ×3 scale-150, 08-17, 08-19, 08-26 wt-pool) | yes |
| agent hook: `dontAsk`, 50 turns, fails open | as stated | `toolPermissionContext:{…mode:"dontAsk",alwaysAllowRules:{…session:[...En,\`Read(/${F})\`]}}`; `tn>=50 ⇒ abort`; `!on ⇒ {outcome:"cancelled"}` on both the 50-turn and no-output paths @17531585. `NUe(): if(e==="dontAsk")return"deny"` @8795764 | yes |
| agent hook 60 s default, Haiku | as stated | not re-read — *inferred* (`Ke=e.model??Em()` seen; timeout constant not located in this pass) | not re-checked |
| agent hook ever ran in the fleet | not claimed | `Agent hook condition was not met`: 11 files, **0** `type:"system"` emissions — the feature has never fired here; its cost figures are code-derived, never observed | n/a |
| `"name":"ProposeGoal"` in 30 d | 0 files; 2 mentions | **0** files; 5 files mention the string (wave docs) | yes |
| `tengu_propose_goal` default false, no local override | `I("tengu_propose_goal",!1)`; 0 hits for 6 Statsig spellings | `function mct(){return I("tengu_propose_goal",!1)}` @24137396 ✓. The client is **GrowthBook** (131 hits, Statsig 0 for the axis's spellings). Override API is stubbed: `readConfigOverrides(){return}`, `setConfigOverride(e,n){return}`, `clearConfigOverrides(){return}` @9794745. `getAllFeatures()` falls back to `readGlobalConfig().cachedGrowthBookFeatures??{}` | yes, and stronger |
| flag state observable? | "cannot test from a subagent" | `~/.claude/.claude.json` `cachedGrowthBookFeatures` (442 keys primary; 610 keys ×3, stamped `cachedGrowthBookFeaturesAt` 2026-09-08): `tengu_propose_goal` **ABSENT in all four** ⇒ default `false`. Also absent: `tengu_rosy_wren` (A03's Task-tools gate). Present: `tengu_saffron_wren:true` ×3, `tengu_hushed_lark:5` ×3, `tengu_umber_kestrel` false/false/true/true | open question #1 **closed: off** |
| `ProposeGoal` in 219 / 220 | 0 / 0 | 0 / 0; 260 = 13 | yes |
| `SubagentStop` in live settings | 0 | 0 in all four accounts | yes — but see § 2 R2 |
| `/goal` is a prompt Stop hook | `KEe()` | `o.sessionHooksRegistry.add(r,"Stop","",{type:"prompt",prompt:t})` @11566244 | yes |
| Stop payload carries `background_tasks`, `session_crons` | yes | schema @9987990, both `.optional()`, descriptions verbatim | yes |
| `/goal` no-progress detector ("no tool use for several turns") | cited from docs, "binary strings hint at" | 0 hits for `no_progress`, `noProgress`, `without progress`+goal, `goal still set`, `returning control`; `tengu_goal_*` telemetry set = {achieved, checkin_injected, cleared, evaluated, failed, proposal_available, proposal_decided, proposed, restored_on_resume} — nothing named for a stall | **inferred**, docs-only |

Commands: settings census `python3 -c "import json;…"` over each `~/.claude*/settings.json`; binary greps
`LC_ALL=C timeout 120 /usr/bin/grep -a -c -F <lit> <exe>`; transcript census `find … -mtime -30 | realpath-dedupe
| xargs -P 8 -n 150 /usr/bin/grep -l -F <lit>` then a Python pass keeping only `type=="system"` records whose
`content` contains the literal.

---

## 2. Recommendation verdicts

### R1 — delete `ENABLE_STOP_REVIEW` (axis 96 %) → **holds, 88 %**
Fact re-verified three ways (three binaries, docs quoted by the axis, no reader on disk). The one thing the
axis under-weighs: a `settings.json` edit is a C10 migration, i.e. an *operator* step (`cc-backlog needs`),
spent on a change with zero behavioral effect. Under the FILED test (who is it for?) this should ride the
next settings migration rather than mint its own row. Failure direction: none on behavior; the cost is
operator attention on a no-op.

### R2 — register `SubagentStop`, "advisory-only (exit 0 + additionalContext)" (axis 88 %) → **refuted as written, 35 %**
- Already staged: `migrations/0014-subagent-stop-registration.sh` (`# migration-class: c10`, `--run` filed
  on row `296cc04bc3fd`, blocked 2026-08-17 and re-blocked 2026-08-18). The axis presents a known,
  filed, operator-gated step as a new cheap win.
- The prescribed mechanism contradicts the hook's own pinned contract, `hooks/subagent-stop.sh:39-41`:
  *"a `decision:"block"` or a `hookSpecificOutput.additionalContext` here does not merely misbehave — it
  extends the turn and increments the harness's consecutive-block counter (capped at 8). This hook
  therefore writes NOTHING to stdout on any path and always exits 0."* Five bats suites pin it.
- The hazard is documented: `docs/plans/SUBAGENT_STOP_HOOK_LOOP.md` (status complete) records three research
  subagents looping to idle under a blocking Stop hook; backlog `56db7fb21284` (done) is a DISPROOF of the
  "no close discipline" framing.
- Failure direction of R2-as-written: **nags in a loop** — `additionalContext` on SubagentStop forces a
  turn on a subagent that may be unable to satisfy it (the exact incident above). The surviving action is
  the operator running migration 0014, which is already in the `cc-do` pile.

### R3 — do not adopt an agent Stop hook; land allowlist rules first (axis 84 %) → **premise refuted, 45 % as written / 80 % for "not now"**
- The load-bearing objection ("no rule matches wrap-ledger.sh / cc-backlog / cc-decide") counted only
  `~/.claude/settings.json`. `.claude/settings.json` in this repo already carries all three families, and
  the binary merges `projectSettings` into `alwaysAllowRules` (`Hm` @11043434). For a session cwd'd in
  claude-infrastructure the judge would NOT be denied those commands. (The rules are relative-path shaped,
  so a judge invoking `bash /abs/path/wrap-ledger.sh` would still miss — a real but different gap.)
- The fail-open path is real and verbatim (`cancelled` on no structured output), so "do not adopt as-is"
  stands on that leg alone. Adopting errs **silent in the dangerous state**; the axis has the direction right.
- The proposed trial's instrument does not exist locally: `tengu_agent_stop_hook_*` is telemetry to
  Anthropic, and the `Hooks: Agent hook …` lines are debug-log-only. A trial "measured against telemetry"
  cannot be measured from this machine without `--debug` capture — the plan needs a local instrument named.
- 0 genuine agent-hook emissions in 6,144 transcripts: every latency/cost figure for this type is
  code-derived, never observed.

### R4 — leave `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` at 8, never 0 (axis 93 %) → **holds, 90 %**
Code and census reproduce exactly. Two confounds the axis does not state: (i) our own Stop chain
self-caps first (`CLAUDE_CONTINUE_MAX`=8, `CC_MECH_MAX`, `CC_SHIP_FLOOR_MAX`), so "6 hits in 30 d" measures
*our* bound more than the harness's headroom — the reading "no pressure on it" is partly an artifact of
where we stop blocking; (ii) the "no-progress detector" the axis names as the real ceiling has no string in
2.1.260 under any spelling tried — it is a docs claim, *inferred*. Neither changes the recommendation, which
is a non-action whose failure direction is correctly stated.

### R5 — read `background_tasks`/`session_crons` in the Stop chain instead of building D8 (axis 90 %) → **refuted as a substitute, 45 %**
- `hooks/goal-inert-watch.sh:50-67` (the repo's own reading of the same field, verified on 2.1.231):
  `background_tasks` is a **backgrounded-only** view (`isBackgrounded===!1` filtered out); every ordinary
  foreground Bash registers `local_bash` with `isBackgrounded:!1`; "AN EMPTY LIST IS NOT EVIDENCE THAT
  NOTHING IS DEFERRING". The axis cites lines 141/147 and not the trap 20 lines above them.
- Backlog `a3eaa0dc1be2` (open: add + venue only) asks for BUSY / IDLE-ARMED / IDLE-DEAF *including* "a
  20-minute gate vs a stuck poll loop" — a foreground-execution question. No Stop payload exists while the
  foreground runs, so the field cannot answer the axis the operator names first.
- The named consumer `scripts/wrap-ledger.sh` runs from `/wrap` inside a turn with no hook stdin; only a
  Stop hook (`operator-readout.sh`, `session-continue.sh`) sees the payload. Reading it there is fine, and
  it does add one honest bit — *backgrounded* work or a cron will wake this session (IDLE-ARMED vs
  IDLE-DEAF) — which is worth having as a ledger fact. That salvage is the 45 %.
- Failure direction of R5-as-written: **silent in the dangerous state** — an empty `background_tasks`
  rendered as "idle, nothing running" while a foreground gate is mid-run is exactly the wrong answer to D8.

### R6 — file `tengu_propose_goal` as `not-yet-true` with a falsifier (axis 92 %) → **holds, 90 %, falsifier corrected**
`bin/cc-backlog:1026-1027` accepts `not-yet-true` and `--falsifier`; no existing row mentions ProposeGoal.
The override conclusion is stronger than the axis knew (stubbed override API, not merely absent spellings).
Correction: the axis's falsifier ("appears in a lead session's tool inventory") needs a human in a lead
pane; a command exists — `jq '.cachedGrowthBookFeatures.tengu_propose_goal' ~/.claude/.claude.json` — and
reads `null` in all four accounts today. Failure direction unchanged (waits on Anthropic; the falsifier
self-retracts). Caveat: the cache is an *editable* file, so a non-durable, soft-denied override vector does
exist (`tengu_gb_refresh_interval_minutes` overwrites it); the axis's "no local override" is true in the
durable sense only.

### R7 — import the `ScheduleWakeup` polling guidance; prefer `Monitor` (axis 87 %) → **refuted, 25 %**
`CLAUDE.md:162` (`cc-await-ping … event-driven wake`) and `commands/handoff.md:616` ("never a
poll-and-hope") already carry the event-driven discipline. `ScheduleWakeup` is bound to `/loop` dynamic
mode and was called 17× in 4 files in 30 d (axis-measured); importing prose about a tool the fleet does
not use into an always-resident file is filler by the house's own Communication Discipline, and restates a
product fact that perishes (memory rule: resident policy must not restate perishable facts). Failure
direction: not silent, not nagging — it spends resident context for no behavior change.

### R8 — do not declare a `type:"prompt"` Stop hook while `/goal` stands (axis 89 %) → **holds, 88 %**
`KEe()` verbatim; per-turn counter verbatim. A non-action with the failure direction correctly stated.

---

## 3. What the axis MISSED that its question required

1. **The settings layers.** "Our configuration" was measured from one file. Permission rules merge across
   user + project + local (`Hm` @11043434), and the project layer already answers R3. Hook registration is
   also **not** fleet-uniform: secondary/tertiary/quaternary lack `PostToolUseFailure` entirely and lack
   `pr-gate.sh`, `escalation-watch.sh` (and two of them `web-entrypoint-ladder.sh`) — 94/95/94 hooks vs 100.
   The axis wrote "identical in all four" (true of the `env` block only, md5 `b8770cdb` ×4).
2. **The flag client is GrowthBook, not Statsig**, and its cache is local and readable
   (`~/.claude/.claude.json → cachedGrowthBookFeatures`). This closes the axis's open question #1 (off) and
   hands A03 a fact: `tengu_rosy_wren` is also absent, so the Task tools are gated by the env var alone.
3. **The repo's own SubagentStop record** — migration 0014, rows `2cc7ee852288`, `7ea31ffa1a08`,
   `56db7fb21284` (DISPROOF, done), `296cc04bc3fd` (blocked, C10), `docs/plans/SUBAGENT_STOP_HOOK_LOOP.md`,
   `HOOK_SURFACE_100P.md:69`. A "search the graveyard before building" miss.
4. **`goal-inert-watch.sh`'s trap (c)** on the very field R5 proposes, 20 lines above the lines the axis cites.
5. **No local instrument for the agent-hook trial** — telemetry-only success/blocking signals.
6. **The upstream feature most relevant to the operator's item (7)** — permission prompts. `prompt`/`agent`
   hook types are legal on `PermissionRequest` and could auto-decide; backlog rows `ce5e5310c457` /
   `7cdf4ea8f10e` (`model-permission-decider.py`) already circle this. Not examined by the axis at all.
7. **The cap census confound** with our own `CLAUDE_CONTINUE_MAX` self-cap, and the docs-only status of the
   "no-progress detector".
8. **105 → 100 hooks**: the store moved under the axis (mtime 16:23 local); a live-store number needs its
   read time stated.

## 4. Failure-direction summary

| rec | adopting errs toward | holds? |
|---|---|---|
| R1 | operator attention on a no-op (C10) | yes |
| R2 as written | nagging loop on subagents (documented incident) | no |
| R3 as written | already done for this repo; the "not now" leg errs correctly toward silence-avoidance | premise no / direction yes |
| R4 | rare loud override (correct) | yes |
| R5 as written | silent-in-dangerous-state (empty list read as idle) | no |
| R6 | waiting on a remote flag, self-retracting | yes |
| R7 | resident-context padding | no |
| R8 | none (non-action) | yes |
