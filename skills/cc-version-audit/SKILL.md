---
name: cc-version-audit
description: Assess whether to advance the Claude Code BINARY version (the eval `claude-next` track and/or the pinned stable `claude`/`cc`) against the latest CHANGELOG, scoped to reso's workflow (Agent Teams, Dynamic Workflows, hooks, launchers). Produces a HOLD/ADVANCE verdict + MANIFEST.jsonl entries that respect the auto-install semantics. Use on "is it safe to move up / upgrade Claude Code", "check our CC version against latest", "should we bump claude-next", or when claude-latest nags about a new version. NOT for Claude MODEL changes (use /model-upgrade) or app-code SDK migrations (use /claude-api migrate).
allowed-tools: Read, Edit, Write, Bash, WebSearch, WebFetch, Workflow, Agent, AskUserQuestion
---

# cc-version-audit — Claude Code binary-version upgrade-safety runbook

Assess advancing the CC **binary** (not the model). Two tracks: an **eval** track (a
`~/.claude-<NNN>` dir, selected by a zshrc `_bin` line) and a **pinned stable** track
(`claude`/`cc` → `~/.claude-versions/`). SSOT ledger: `~/.claude-versions/MANIFEST.jsonl`.
Related memories: `hardened-version-management`, `feedback-detect-cc-runtime-not-claude-version`,
`version-identity-is-the-running-process-not-the-launcher`,
`resident-policy-must-not-restate-perishable-facts`.

🚨 **This file names NO version as current, deliberately.** Every number it used to state
went stale: from 2026-07-10 it read "eval 2.1.183 / stable 2.1.114", and measured 2026-08-11
the eval track was on **2.1.220** — 37 releases and five MANIFEST entries later, none of which
this file knew about. A runbook that restates a perishable fact has no path to learn it
changed (same defect the CLAUDE.md ship-policy table was rewritten to delete). Read every
number live via Step 0/1. **A hardcoded current-version anywhere below is a bug in this file.**

## Step 0 — Detect the REAL running runtime (never `claude --version`)
`claude`/`cc` are shell functions resolving the stable-pinned launcher, so `claude --version`
reports the STABLE pin's number even inside an eval-track session — plausible, wrong, and
silent. In order of authority:
- **`ps -o command= -p $PPID`** — the running process's own argv, carrying the real
  `~/.claude-<NNN>/node_modules/.bin/claude` path. The only reading that cannot lie, because
  it interrogates the process rather than a name that resolves elsewhere.
- `echo $CLAUDE_CODE_EXECPATH` → `.../.claude-<NNN>/...`
- `echo $AI_AGENT` → `claude-code_2-1-XXX_agent`
- `echo $CLAUDE_CODE_EXECPATH` → `.../.claude-183/...` ⟹ eval/2.1.183
- Tool availability: `TeamCreate`/`TeamDelete` present ⟹ 2.1.114; absent ⟹ implicit-team model (≥2.1.178).

## Step 1 — Establish the target (do NOT trust the `stable` dist-tag)
```bash
npm view @anthropic-ai/claude-code version            # latest published
npm view @anthropic-ai/claude-code dist-tags --json   # stable / latest / next
cat ~/.claude-versions/current; tail -3 ~/.claude-versions/MANIFEST.jsonl
```
The npm `stable` dist-tag is **not** a reliability signal — 2026-07 it pointed at
2.1.197, which sat inside a self-destructing-daemon regression window. Judge from
the CHANGELOG + churn, never the tag. (2026-08: it pointed at 2.1.221 while `latest`
was 2.1.228 — the trap recurs, so this is a standing property, not an anecdote.)

## Step 1b — Discharge the STANDING HOLD *before* reading anything else 🚨

**A previous audit HELD, and its reasons are the first thing this audit must answer.**
Without this step the hold's reasoning lives only as prose in a MANIFEST note, and each
audit re-derives it from scratch or — worse — advances past it without noticing. Read the
last non-advancing entry and extract its held-open issue list:

```bash
# the most recent skip entry carrying a REVISIT TRIGGER (not merely tail -3, which drifts)
grep -o '"version":"[^"]*"' ~/.claude-versions/MANIFEST.jsonl | tail -5
python3 - <<'PY'
import json
rows=[json.loads(l) for l in open('/Users/chrisren/.claude-versions/MANIFEST.jsonl') if l.strip()]
held=[r for r in rows if 'REVISIT' in (r.get('notes') or '')]
print(held[-1]['version'] if held else 'no standing hold'); print(held[-1]['notes'] if held else '')
PY
```

**Then check EVERY held-open issue for resolution** — one line each in your output, and an
explicit `still open` is a verdict, not a gap:

| Issue | Held because | Discharged when |
|---|---|---|
| **#84974** | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` does not disable nesting (2.1.225); effective depth off-by-one | closed/fixed, **or** a release restores a spawn ceiling |
| **#85264** | fork subagents spawn unauthorized nested agents (2.1.226) | closed/fixed |
| **#85015** | two bg subagent workers → 46 GiB, jetsam froze a 16 GB Mac (2.1.222/224) | closed/fixed |
| **#84224 · #85154** | auto-updater installs into the PATH-resolved npm prefix / yields a stub with no `bin/claude` and no rollback | closed/fixed — this is the UPGRADE MECHANISM, so it gates its own remedy |
| **#85886 #85497 #85412 #85690 #85764** | cross-session inbox: socket never bound, same-second bind race, self-delivery, ListAgents omissions | the *race* fixed, not merely first-session-after-upgrade |

🚨 **The ceiling that was REMOVED is the load-bearing one.** 2.1.224 deleted the
200-subagent-per-session cap. That reads as a feature in the changelog ("long-running
sessions no longer refuse new agents") and is therefore filed under improvements, not risks
— so grep the whole gap for *restored / limit / cap / ceiling / depth* and treat a silent
band as **still uncapped**. This box fans out N=12 by default and has taken four
memory-storm kernel panics; an unbounded spawn is the failure mode that reaches the kernel.

**Slice floor:** read the CHANGELOG from the version we ACTUALLY RUN (Step 0), never from
`latest` minus a few. A fix for a held-open issue can land in any release in the gap, and
skipping the early ones is how a discharged blocker gets missed.

## Step 2 — Fetch + slice the CHANGELOG gap
```bash
curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md -o /tmp/cc-changelog.md
grep -n "^## 2\.1\." /tmp/cc-changelog.md | head -40   # locate the gap: our-version → latest
```
Read every version between the running version and the target.

## Step 3 — Fan out the assessment (Dynamic Workflow, 3 axes + adversary)
Fire a workflow (or subagents) with these reso-workflow axes — each reads the
changelog slice AND reso's actual configs, rates each change BLOCKER/CAUTION/
IMPROVEMENT/NEUTRAL:
1. **Agent Teams / effort / worktree** — implicit-team spawn, TeammateIdle reap,
   it2/tmux pane backend, per-member effort, worktree isolation, depth-cap/fork.
2. **Background subagents / Dynamic Workflows / model+cost defaults** — background-
   by-default subagents, workflow `agent()`/schema behavior, daemon reliability +
   regression WINDOWS, Explore model/cost, default-model flip vs reso's pins.
3. **Hooks / permission modes / auto-mode / launchers** — matcher semantics,
   SessionStart streaming/idle-reap, Stop/Notification, auto-mode destructive-cmd
   blocks + transcript-tamper rules, default-permission-mode flip, AskUserQuestion.
Then an **adversarial** agent (web-enabled): sweep
`github.com/anthropics/claude-code/issues` for OPEN regressions vs the target band
that the changelog omits; default to flagging risk; return a sharp ≤450-token verdict.

## Step 4 — Churn-signal heuristic (the load-bearing judgment)
A version that FIXES a daemon/hook regression means that subsystem was recently
broken. **Set the safe floor at the LAST fix in a regression cluster, not the first
version that looks clean.** (2026-07: 2.1.196 shipped daemon self-kill fixed only
across 199–203 → safe floor 2.1.203, not the 2.1.197 `stable` tag.) A version with
<1 week field exposure is a moving target regardless of changelog.

## Step 5 — Verdict + MANIFEST governance (the auto-install trap)
Two INDEPENDENT guards hold the pin — both must stay intact (verified 2026-07-09):
- **CC's built-in self-updater is off**: `DISABLE_AUTOUPDATER=1` is exported by the
  launcher (`~/bin/claude-latest`, ~line 333). *(The 2026-07 audit's live analysis
  miscalled this `DISABLE_AUTOREPATCH` — no such var; the real one is
  `DISABLE_AUTOUPDATER`. Grep the launcher, don't trust the recalled name.)*
- **The launcher's own bump is default-deny**: `claude-latest` reads
  `MANIFEST.jsonl` and **auto-installs a newer version ONLY if its `status` is
  `stable` or `candidate`**; `skip` or no-entry ⟹ REFUSED (stays on installed).
So a `candidate` entry TRIGGERS the advance — that is the trap.
- **To HOLD**: every assessed version → `status:"skip"` (even the conditional
  target). Put the conditional-advance playbook in that version's `notes`.
- **To ADVANCE**: `status:"candidate"` ONLY when actually ready to install, gated
  behind the pre-flight (Step 6). `stable` only after soak.
Entry shape (append after the last line via Edit, never overwrite):
`{"version":"X","status":"skip|candidate|stable","date_added":"<ISO>","notes":"<why + citations + [[memory-link]]>"}`

## Step 6 — Pre-flight gate before ANY promotion (reso-specific)
Before flipping a version to `candidate`:
- Live **TeammateIdle + SessionStart + `shutdown_request`** smoke test on a throwaway team.
- Confirm **`--permission-mode auto` still resolves non-blocking** (2.1.200 flipped
  the DEFAULT to Manual; auto is not the default anymore).
- Set **AskUserQuestion idle-timeout** in launcher profiles (2.1.200 stopped auto-continue).
- Audit teammate `Agent()` spawns for **explicit `model:`** (2.1.197 default = Sonnet 5;
  bare spawns silent-demote).
- Update the **Explore = Haiku ~70× cheaper** assumption in `research-subagents.md`
  if ≥2.1.198 (Explore now inherits lead model, capped opus).

## Standing reso landmines (recurring — check every audit)
| Signal | Status |
|---|---|
| Default permission-mode flip (2.1.200 → Manual) | CAUTION — reso pins `auto`, verify it survives |
| Default model flip (2.1.197 → Sonnet 5) | NEUTRAL for pinned lead; CAUTION for bare teammate spawns |
| Explore model (2.1.198 → opus not Haiku) | COST regression — re-price fan-outs |
| Background-daemon regression window | BLOCKER until the LAST fix in the cluster |
| Effort-override (2.1.186 leader-inherit) | NON-ISSUE — project settings.local.json wins |
| Hook matchers (2.1.191 comma / 2.1.195 hyphen) | NON-ISSUE — reso uses `|` + exact MCP names |
| **Write tool may overwrite an unread file (2.1.228)** | **CAUTION** — newer models no longer need a read first. Directly loosens the INTEGRATE-never-overwrite discipline; the `backup-before-write` PreToolUse hook is now the ONLY thing standing between a model and a silent plan-file rewrite. Verify that hook fires before advancing. |
| **Subagent-per-session cap REMOVED (2.1.224)** | **CAUTION** — the 200-spawn ceiling is gone; only concurrency + depth remain. `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` becomes the sole runaway bound. Re-verify it still reaches the child. |
| **Native cross-session `SendMessage`/`ListAgents` (2.1.224-228)** | **ASSESS, do not silently adopt** — this box already has a home-grown substrate (`cc-notify`, mailbox, `cc-await-ping`). Three consecutive releases of fixes to the native one = a churning subsystem. Overlap is an opportunity AND a double-delivery hazard. |
| **Session cleanup / plugin-cache deletion (2.1.228 fixes)** | **READ CAREFULLY every audit** — 228 fixed cleanup deleting a project's *memory folder* contents, and plugin-cache GC deleting a cache whose only version is a **symlinked dev checkout**. This box's entire `~/.claude` is per-file symlinks into a git checkout, so any GC that follows symlinks is catastrophic here. Treat symlink-following cleanup as a standing blocker class. |
| **`-p` + `--mcp-config` not connected before first turn (fixed 2.1.221)** | On ≤2.1.220 the model emits tool calls as literal text in print mode. Matters wherever a launcher composes `--mcp-config` into headless fires. |

## Output
A briefing: (1) one-line VERDICT (hold vs target version, per track), (2) blockers +
mitigations, (3) cautions to re-verify, (4) net improvements, (5) recommended action
+ MANIFEST entries. Then: write the MANIFEST entries, write/append a
`claude-code-<range>-*.md` memory + MEMORY.md index line. Never advance a track
without the Step 6 gate.

## Appendix — extract a built-in command's hidden prompt from the binary
When the CHANGELOG describes a new built-in command (e.g. `/checkup`, alias of
`doctor`) but not what it *actually does* to your config, read its orchestration
prompt straight out of the binary — the ground truth the changelog paraphrases.
The main npm package is now a small **wrapper stub** (~150 KB unpacked); the real
CLI ships as a per-platform Bun single-executable (`claude.exe`, ~215 MB) delivered
as an `optionalDependencies` package (`@anthropic-ai/claude-code-<platform>`, one
per arch, version-matched to the main pkg). Pull it read-only into `/tmp` (this
NEVER touches the pinned install):
```bash
cd /tmp && npm pack @anthropic-ai/claude-code-darwin-arm64   # platform pkg for THIS arch
tar xzf anthropic-ai-claude-code-darwin-arm64-*.tgz
bin=$(find package -name claude.exe -o -name 'claude' -type f | head -1)  # SEA binary
strings -n 8 "$bin" > /tmp/cc-bin-strings.txt
grep -nE 'doctor|checkup|Check [0-9]|DISABLE_DOCTOR_COMMAND' /tmp/cc-bin-strings.txt
```
The full numbered-check prompt (`/checkup` runs Check 0–8) extracts verbatim; the
technique generalizes to **any** built-in command's hidden system prompt. Caveats:
a naive `grep` catches noise (the binary also embeds the Workflow tool's own
prompt — anchor on the command's unique markers); pick the platform pkg matching
your arch (`-darwin-arm64` / `-darwin-x64` / `-linux-x64` / `-linux-arm64` / `-win32-x64`). Governance note: the
`doctor`/`checkup` command is **killable via `DISABLE_DOCTOR_COMMAND`** — set it if
its auto-fixes (disabling rarely-fired-but-deliberate skills, moving always-loaded
CLAUDE.md rules, turning off load-bearing slow hooks) would fight a deliberate
config. Its Check 6 (version currency) already no-ops under `DISABLE_AUTOUPDATER=1`
(Step 5), so it will not nag to `claude update` against the pin.
