# holds.md — the standing HOLD and the reso landmines (phase P2)

**This is the only file in the skill allowed to carry dated or version-specific facts.** Every
other file reads them live. The tables below are an INDEX into the MANIFEST, not the source of
truth: the latest `REVISIT` row is. When they disagree, the row wins and this file is stale; fix
it in the same diff as your audit.

## 1. Discharge the standing HOLD before reading anything else

A previous audit HELD (or advanced the fleet over held-open issues), and its reasons are the first
thing this audit must answer. Without this step the hold's reasoning lives only as prose in a
MANIFEST note, and each audit re-derives it from scratch or advances past it without noticing.

```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser('~/.claude-versions/MANIFEST.jsonl')
rows = [json.loads(l) for l in open(p) if l.strip()]
held = [r for r in rows if 'REVISIT' in (r.get('notes') or '')]
print(held[-1]['version'], held[-1]['status'], held[-1].get('date_added')) if held else print('no standing hold')
print(held[-1]['notes'] if held else '')
PY
```

(Not `tail -3`: the last rows drift, and a band audit writes several rows with one note.)

**Then check EVERY held-open issue for resolution** — one line each in your output. An explicit
`still open` is a verdict, not a gap. `gh issue view <n> -R anthropics/claude-code --json state,stateReason`
reads each one; `NOT_PLANNED` is a closure, not a fix, and does not discharge.

### Held-open issues — index as of the 2.1.284 row (2026-09-28)

| Issue | Held because | Discharged when | State at that row |
|---|---|---|---|
| **#84974** | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` did not disable nesting (2.1.225); effective depth off-by-one | closed/fixed, **or** a release restores a spawn ceiling | open (gate #15 reads the binary's own depth gate each run) |
| **#85264** | fork subagents spawn unauthorized nested agents (2.1.226) | closed/fixed | open |
| **#85015** | two bg subagent workers → 46 GiB, jetsam froze a 16 GB Mac (2.1.222/224) | closed/fixed | open |
| **#84224 · #85154** | auto-updater installs into the PATH-resolved npm prefix / yields a stub with no `bin/claude` and no rollback | closed/fixed — this is the UPGRADE MECHANISM, so it gates its own remedy | #84224 open; #85154 closed not-planned |
| **#85886 #85497 #85412 #85690 #85764** | cross-session inbox: socket never bound, same-second bind race, self-delivery, ListAgents omissions | the *race* fixed, not merely first-session-after-upgrade | #85886 fixed (2.1.228); #85497 #85764 open; #85412 #85690 closed not-planned |

Cautions that row carried into the flip (re-check each on the next audit): the `sonnet` alias
moved to Sonnet 5.5 in 2.1.284 (pin by id); `ultracode` no longer forces xhigh (2.1.284);
`rm -rf "$(...)"` asks, then denies after 2 min (2.1.281); open #97888 (trust flag reverting),
#97763 (subagent `output_tokens` undercount), #97687 (opus subagent silently falls back to an
older opus after a cyber refusal).

Pre-audit of the 2.1.285–2.1.289 band (2026-10-03, no MANIFEST row yet; evidence in
`docs/research/claude-code-mods-2026-10-03/REPORT-289.md`). Re-check each when this band is audited:
- **Target 2.1.289; never 2.1.285–2.1.287.** 2.1.285 caps background Bash at 30 min in every
  session (narrowed to unattended sessions only in 2.1.288), which cuts the 3300 s `cc-await-ping`
  arm; 2.1.287 drops earlier thinking when it `--resume`s a session started on 2.1.286 or older,
  which is exactly the `lr-upgrade.sh` relaunch.
- **2.1.287 changes the revoked-login text** to "OAuth token revoked", so the reopen trigger at
  `docs/plans/MASTER_ACCOUNT_FACTS.md:141-142` (a grep for "has been revoked") goes blind; key it
  on the `authentication_failed` error field instead.
- **Restyled permission prompts (2.1.286–2.1.287):** run `tests/pane-modal.bats` against the
  candidate and capture one live pane with stacked prompts; a "2 of 5" header may defeat the
  anchor at `hooks/lib/pane-modal.sh:160`.
- **check13 passes on any one connected MCP server;** compare each server against the 2.1.284 run.
- **"Shared agents" is not a feature.** @ClaudeCodeLog's summary misread the 2.1.289 mods-API
  line (`agent.spawn` now fires *for* a teammate spawn). It loosens no cap; the depth guards are
  unchanged in the 2.1.289 strings. If mods are ever adopted, a mod's `$.agent.spawn` appears to
  bypass the PreToolUse(Agent) spawn budgets (inferred from the types, unprobed): ban it in fleet
  mods until probed.

🚨 **The ceiling that was REMOVED is the load-bearing one** (historical: 2.1.224 deleted the
200-subagent-per-session cap). It reads as a feature in the changelog ("long-running sessions no
longer refuse new agents") and is therefore filed under improvements, not risks — so grep the
whole gap for *restored / limit / cap / ceiling / depth* and treat a silent band as **still
uncapped**. This box fans out N≈10 by default and has taken four memory-storm kernel panics; an
unbounded spawn is the failure mode that reaches the kernel.

## 2. Standing reso landmines (recurring — check every audit)

| Signal | Status |
|---|---|
| Default permission-mode flip (2.1.200 → Manual) | CAUTION — reso pins `auto`; gate #3/#11 prove it survives |
| Default model flip (2.1.197 → Sonnet 5; the `sonnet` alias itself moved again in 2.1.284) | NEUTRAL for a pinned lead; CAUTION for bare teammate spawns — audit `Agent()` calls for an explicit `model:` |
| Explore model (2.1.198 → the lead's model, capped at opus, not Haiku) | COST regression — re-price fan-outs; pin `model: "haiku"` where retrieval is the job (research-subagents skill) |
| Background-daemon regression window | BLOCKER until the LAST fix in the cluster (audit.md § Churn) |
| Effort-override (2.1.186 leader-inherit) | NON-ISSUE — project settings.local.json wins |
| Hook matchers (2.1.191 comma / 2.1.195 hyphen) | NON-ISSUE — reso uses `\|` + exact MCP names |
| **Write tool may overwrite an unread file (2.1.228)** | **CAUTION** — newer models no longer need a read first. Directly loosens the INTEGRATE-never-overwrite discipline; the `backup-before-write` PreToolUse hook is now the ONLY thing standing between a model and a silent plan-file rewrite. Verify that hook fires before advancing. |
| **Subagent-per-session cap REMOVED (2.1.224)** | **CAUTION** — the 200-spawn ceiling is gone; only concurrency + depth remain. `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` becomes the sole runaway bound. Gate #6 (delivery) and #15 (effect) re-verify it. |
| **Native cross-session `SendMessage`/`ListAgents` (2.1.224-228)** | **ASSESS, do not silently adopt** — this box already has a home-grown substrate (`cc-notify`, mailbox, `cc-await-ping`). Three consecutive releases of fixes to the native one = a churning subsystem. Overlap is an opportunity AND a double-delivery hazard. |
| **Session cleanup / plugin-cache deletion (2.1.228 fixes)** | **READ CAREFULLY every audit** — 228 fixed cleanup deleting a project's *memory folder* contents, and plugin-cache GC deleting a cache whose only version is a **symlinked dev checkout**. This box's entire `~/.claude` is per-file symlinks into a git checkout, so any GC that follows symlinks is catastrophic here. Treat symlink-following cleanup as a standing blocker class. |
| **`-p` + `--mcp-config` not connected before first turn (fixed 2.1.221)** | On ≤2.1.220 the model emits tool calls as literal text in print mode. Matters wherever a launcher composes `--mcp-config` into headless fires. |
| AskUserQuestion stopped auto-continue (2.1.200) | set the AskUserQuestion idle-timeout in launcher profiles |
