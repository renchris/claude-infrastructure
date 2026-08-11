---
status: open
---

# MCP MEMORY 100P — implementation plan (research → deployed-and-live)

**Created:** 2026-08-11 · **Owner:** implementation-lead session (recycled from the research session)
**Verdict being implemented:** `docs/research/mcp-memory-groundup-2026-08-10.md` (+ 10 artifacts, all on trunk) —
zero-entry scoping + free wins + no-inherit + lifecycle bounds + tree-aware accounting; shared daemon REJECTED.
**Backlog successors this plan discharges:** `572b6341aa12` (reso scoping+free wins) · `87ef04ead50d` (browsermcp
elimination) · `eece54939e7f` (no-inherit fan-out) · `819839ed24b3` (fnm-space actuator blindness) ·
`e3fb627bc57a` (coldcompile unwired) · `ef28f9bb11e6` (PER_MB tree) · plus existing `aac347ddc003` (inert MCP probe).

**Scope (frozen):** drive the six MCP-memory successors to implemented + verified + landed + live in their owning
repos/configs — W1 reso scoping & free wins (parity-evidenced), W2 browsermcp elimination, W3 no-inherit for agent
fan-out (+ the teammate probe that closes 04's named gap), W4 enforcement/accounting fixes (fnm-space census+actuator
with class-test exclusion + tests, PER_MB tree derivation, coldcompile wire-or-retire via c10), W5 end-state
verification sweep — each wave's verification commands RUN AND PRINTED, each backlog id closed with evidence.

---

## Phase 0 · Agent Team Orchestration (FIRST — read before any work)

**EXECUTION LOCUS PER WAVE** (S = dispatched handoff session, the default; no justification needed):

| Wave | Locus | Worktree / cwd | Account | Why-note |
|---|---|---|---|---|
| W1 reso scoping + free wins | **S** | fresh worktree of **reso-management-app** (its own `new-worktree.sh`) | auto | cross-repo; reso's CLAUDE.md + ship policy read LIVE at execution (perishable-fact rule) |
| W2 browsermcp elimination | **S** | claude-infrastructure worktree (edits live in `~/.claude*.json` + settings — config-side, not tracked here except docs) | auto | small; may merge into W1's session if the lead prefers ONE config-touching session at a time (serialize — both touch `~/.claude.json`) |
| W3 no-inherit fan-out | **S** | claude-infrastructure worktree | auto | touches spawn surfaces (`handoff-fire.sh`, agent-teams env) — code + tests |
| W4 enforcement/accounting | **S** | claude-infrastructure worktree | auto | safety-actuator change (SIGSTOP selection predicate) — needs tests-in-same-diff discipline; the riskiest wave, keep it isolated |
| W5 verification sweep | **L** (lead-inline) | shared checkout, read-only | — | pure reads + one census; no writes beyond plan updates — cheaper than a fire |

- **Dependency graph:** W1 ∥ W3 ∥ W4 (independent files); W2 **after or with** W1 (both edit `~/.claude.json` —
  single-owner rule for that file: ONE session holds it at a time); W5 after all.
- **Spawn order:** fire W1 + W3 + W4 in one sitting (three `handoff-fire.sh` calls, `--notify-back` armed);
  W2 folds into W1's brief (same session) — its file overlap makes a separate session a conflict risk, and it is
  ~30 min of config edits. Lead collects pings, lands nothing itself.
- **Fire recipe per wave** (from global CLAUDE.md § Agent Teams — `--goal` mandatory):
  `scripts/handoff-fire.sh --prompt-file /tmp/fire-mcp-w<N>.txt --worktree <branch> --notify-back <pane> --account auto --split-right --goal '<the wave's DoD line below> — proven by <the wave's verification command> run and printed; do not <the wave's constraint>'`
- **Teams inside waves:** W1 and W4 are each single-session-sized (≤6 files); spawn in-session teammates only if a
  wave's session judges its diff >500 LOC (unlikely). Research subagents (read-only) free as needed.
- **Lead context budget:** the recycled lead holds ≥50% window for wave briefs, ping collection, and the W5 sweep;
  succession point = after W5's verification block prints green → wrap + close. If the lead nears 75% before all
  pings return: persist state to THIS plan file, `handoff-fire.sh --recycle` again.
- **Custody:** every `--notify-back` fire records a debt (cc-custody); collect → land → `cc-custody return` per wave.

---

## W1 · reso: scope-to-need + free wins (backlog `572b6341aa12`)

**Repo:** `~/Development/reso-management-app` (work in ITS worktree; read ITS `CLAUDE.md` + `scripts/land-status.sh`
before landing — landing/deploy cost is reso's fact, not this plan's).

Current stanza (verified 2026-08-10): `.mcp.json` → `chrome-devtools: {command:"npx", args:["chrome-devtools-mcp@latest","--isolated"]}`
(+ `uidotsh`/`motion`/`motion-plus` http — untouched). Inherited by ~79 worktrees; eager ~280-340 MB/session
(probe-proven 550-822 ms after launch, headless approval-bypass included); used in 3.2% of transcripts,
2,384 calls/30 d, call mix: `evaluate_script` 1205 · `navigate_page` 341 · `take_screenshot` 316 · `new_page` 171 ·
`emulate` 114 · `select_page` 65 · `resize_page` 58 · `list_pages` 39 · `take_snapshot` 25 · console 17 · `click` 14.

**Tasks, in order:**
1. **Free wins first (zero workflow change, ~60% of each chain):**
   a. Pin + direct-invoke: `npm i -g chrome-devtools-mcp@<current>` (or vendored path), stanza `command` → the
      resolved bin, dropping `npx`/`@latest` (−1 resident process 71-156 MB, −0.8 s, version deliberate; two
      versions measured running side-by-side today). Two worktrees route via `scripts/mcp/chrome-devtools-mcp.sh` —
      apply the same change inside that wrapper.
   b. `env.CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS: "1"` in the stanza (kills the ~88-110 MB telemetry watchdog).
   c. `env.NODE_OPTIONS: "--max-old-space-size=1024"` (leak bound; #2291 still open upstream; real node binds it).
   d. Delete the dead persistent profile `~/.cache/chrome-devtools-mcp/chrome-profile` (1.3 GB, untouched since
      Jun 5, bypassed by `--isolated`) — confirm no non-`--isolated` config can still reach it first (see 2.).
   e. Reconcile the duplicate: `~/.claude.json` → `projects["…/reso-management-app"].mcpServers.chrome-devtools`
      (`--channel=stable --viewport=1440x900`, NO `--isolated`) conflicts with the repo stanza — delete the
      `~/.claude.json` entry (no fleet session reads that file, but it shadows for anyone who ever does).
2. **Parity evidence, then the opt-in flip (H):** build the parity checklist for the call mix above using
   `agent-browser` CLI / `chrome-devtools-mcp --browserUrl` attach (skills: `dia-agent`,
   `autonomous-authenticated-web-access`); run it against a real reso verification task. If parity holds →
   move the stanza out of `.mcp.json` into an opt-in shape (`.mcp.browser.json` + documented `--mcp-config` opt-in,
   or `disabledMcpjsonServers` default + enable-where-used) so non-browser sessions pay **0 B, 0 tokens**.
   A TRUE capability gap (something only the eager MCP shape can do) → keep the stanza, document why, close the
   backlog item with that evidence instead — the flip is evidence-gated, not forced.
3. **Wave-fired sessions:** whatever shape lands, verify a `-p` headless run in a reso worktree no longer spawns
   the chain unrequested (the headless bypass loads `.mcp.json` unconditionally — so the fix must be in the FILE,
   not in approval lists).

**Verification (run + print):** `ps -axo pid,ppid,rss,command | /usr/bin/grep -E 'chrome-devtools|npm exec' | /usr/bin/grep -v grep`
after launching one fresh interactive reso session AND one `-p` probe — expected: no unrequested chain (opt-in
shape) or a 2-process pinned chain with telemetry absent (free-wins-only shape). Parity checklist output attached.
**DoD:** free wins landed in reso; flip landed OR gap-evidence recorded; `572b6341aa12` closed with evidence.
**Constraint:** never bare `git push` in reso; read reso's own landing policy live.

## W2 · browsermcp elimination (backlog `87ef04ead50d`) — folded into W1's session

Sites (all verified 2026-08-10): `~/.claude.json` user-scope `mcpServers.browsermcp` + local-scope
`projects["…/reso-upgrade-dependencies"].mcpServers.browsermcp`; `enabledMcpjsonServers:["browsermcp","agent-browser"]`
in `~/.claude/settings.json:424-425` AND `~/.claude-secondary/settings.json:424-425` (+ mirror dirs if present —
sweep all `~/.claude*/settings.json`); 4 project `settings.local.json` (personal · taxes-2026 · technical-analysis ·
reso-management-app:500-501); `$CFG/.mcp.json` browsermcp entry (inert — CC reads project-root only) +
`bin/browsermcp-wrapper.sh` (this repo — retire: git rm + note, it references a dead server).
Evidence basis: 0 invocations / 3,504 transcripts / 30 d; upstream frozen 2025-04-11; port-9009 `kill -9`
singleton makes per-session spawning invalid; capability covered by `agent-browser --cdp` + `--autoConnect`.
**Config-write discipline:** `~/.claude.json` is written by live sessions — edit with `jq` on a quiesced copy +
atomic `mv`, or via `claude mcp remove` from a session on that config dir; never hand-edit mid-write.
**Verification:** `rg -l 'browsermcp' ~/.claude*/settings.json ~/.claude.json` → only historical/doc hits;
`claude mcp list` in an affected project shows no browsermcp row. **DoD:** all sites clean; wrapper retired;
`87ef04ead50d` closed. **Constraint:** touch only browsermcp keys — the `agent-browser` entry in
`enabledMcpjsonServers` stays (it is the CLI's skill hook, not a server).

## W3 · no-inherit for agent fan-out (backlog `eece54939e7f`)

The measured mechanism: headless/`-p`/SDK processes load project `.mcp.json` stdio servers UNCONDITIONALLY
(approval ignored — 04 Runs E/E2); in-process Task subagents SHARE the parent's client (04 Run G — no multiplier);
separate-process `claude.exe --agent-id` teammates bootstrap from their cwd (corpus-observed once,
`census-fleet.md:400`; 04's one named gap).

**Tasks:**
1. **Close 04's gap first (one cheap probe):** fire one teammate (`Agent` with name) from a throwaway session
   cwd'd in a reso worktree carrying a stdio `.mcp.json` (post-W1 shape may already remove it — run this BEFORE
   W1 lands, or against a fixture dir with a fake logging server, which is free); record whether the teammate
   process spawns its own chain. This decides whether 2. targets teammates or only fired sessions.
2. **Per-fire controls at the spawn surfaces (this repo):** `scripts/handoff-fire.sh` — add an opt-out that
   composes `--strict-mcp-config` (or `--setting-sources` excluding project) into the launched command for
   research/non-browser fires; default ON for fires whose brief does not declare browser work, overridable per
   fire. Same for any other launcher that starts headless workers (`boot-resume-launch.sh`, cc-dispatch path —
   grep `-- print\|-p ` in scripts/ to enumerate the actual sites; enumerate, don't assume).
3. **Mode-independent floor:** where a worktree/profile should NEVER load browser MCP (research fixtures, infra
   worktrees), set `disabledMcpjsonServers` in that scope's settings — the only control the headless bypass
   respects.
4. Tests: bats fixture with a fake logging stdio server in a scratch project — assert a default fire does NOT
   spawn it and a `--with-mcp` fire DOES (positive control; a guard that cannot fail proves nothing).

**Verification:** the bats suite green + one real fired session's spawn-log excerpt printed showing no MCP child.
**DoD:** controls landed + tested; probe result recorded in the plan; `eece54939e7f` closed.
**Constraint:** never widen to blocking http servers (they cost nothing) — scope is stdio project servers only.

### Task 1 probe — DONE 2026-08-11, closing 04's named gap: **teammates DO inherit, and no per-fire flag can reach them**

Measured on 2.1.220 against a fake logging stdio server (`tests/fixtures/mcp-noinherit/fake-stdio-server.py`)
declared in a project `.mcp.json`, with each START line self-attributing by recording its PARENT's argv.

| arm | result |
|---|---|
| `Agent({name})` teammate, server UNAPPROVED | **no spawn** — and this is the trap, not the answer |
| `Agent({name})` teammate, server APPROVED | **spawns its own server process** — fake-server pid 47669 whose ppid 46888 IS the `claude.exe --agent-id w3probe2@…` process |
| teammate process shape | separate OS process, `cwd` = the parent session's cwd, launched `cd <cwd> && env … claude.exe --agent-id …` |
| parent's `--strict-mcp-config` reaching a teammate | **no** — read from the binary, the spawn argv is an enumerated set: `--agent-id --agent-name --team-name --agent-color --parent-session-id [--plan-mode-required] [--agent-type] [--permission-mode --effort --model]`. No MCP flag exists in it to inherit |
| env-carried MCP kill-switch | **none exists** — the only MCP env lever in the binary is `CLAUDE_CODE_SKIP_PLUGIN_MCP_SERVERS` (plugin scope, not project) |

**Why the first row nearly became a wrong verdict.** The unapproved arm returned zero spawns, which reads
as *"teammates don't inherit project MCP — nothing to fix."* It is instead the approval gate doing its job:
`claude mcp list` in the same cwd reported `⏸ Pending approval` for the same server, i.e. the teammate had
read the file and declined. Granting approval flipped the result immediately. A separate-process teammate
is therefore an ORDINARY session for MCP purposes — approval-gated like an interactive one, unlike `-p`
which ignores approval entirely — and reso, which sets `enableAllProjectMcpServers: true`, is precisely the
configuration where every teammate starts its own chrome-devtools. That matches the corpus observation this
gap came from (`census-fleet.md:400`; 2 of 5 live chains belonging to teammates in one worktree) and it
means the 13-chains-per-wave multiplier is real rather than inferred.

**Consequence for the targeting question the probe existed to answer:** per-fire flags cover fired
SESSIONS only. Teammates are reachable exclusively through `disabledMcpjsonServers` in the scope's
settings (Task 3) — which is why that task stopped being a nice-to-have floor and became the only
teammate control that exists.

### Tasks 2-4 — DONE 2026-08-11

**The flag the plan proposed above is the one form that must NOT be used.** Three candidates measured
against one project stdio server plus the account's real user-scope http servers:

| control | project stdio | user-scope http | project settings/hooks |
|---|---|---|---|
| (none) | STARTED | connected | loaded |
| `--setting-sources user,local` | blocked | connected | **DROPPED** |
| `--strict-mcp-config` | blocked | **DROPPED** | loaded |
| `--strict-mcp-config --mcp-config <user-scope passthrough>` | blocked | connected | loaded ← **shipped** |

`--setting-sources` excluding project also excludes a repo's `.claude/settings.json`, and reso's carries
`hooks` and `permissions` — so that form would silently disarm a repo's own hooks in every fired session,
a blast radius far outside this wave. Bare `--strict-mcp-config` empties the server list entirely, taking
the http servers W3's own constraint protects (an http server holds no local process, so blocking it saves
nothing). The shipped control re-adds the target account's user-scope non-stdio servers through
`--mcp-config`, which is what makes it surgical.

- `scripts/lib/mcp-noinherit.sh` (NEW) — one composer, `cc_mcp_noinherit_args`. Default ON; auto-disarms
  when the brief names an MCP tool or browser server (`mcp__…`, browsermcp, chrome-devtools, agent-browser,
  claude-in-chrome) so a fire is never broken by its own isolation; `CC_MCP_NOINHERIT=off` kill-switch.
  It returns its decision in GLOBALS, not on stdout: the first wiring used `$( … )`, whose subshell
  swallowed the reason and shipped a dry run reading `mcp: (undecided)` with the flags correctly composed.
- `scripts/handoff-fire.sh` — `--with-mcp` opt-out; composition wired into the typed command; the decision
  printed as an `mcp:` line in the dry run. Also `probe_account()` now runs `--strict-mcp-config` (it calls
  no tool; its `cd /tmp` immunity was an accident of cwd, not a property of the probe).
- `scripts/headless-precondition-probe.sh`, `bin/cc-notify` (cloud transport) — same one-flag fix.
- `.claude/settings.json` — `disabledMcpjsonServers: ["chrome-devtools","browsermcp"]`, the mode-independent
  floor for this repo and its worktrees. Measured: this key in PROJECT scope takes a headless session's own
  stdio STARTs 1 → 0 while the http servers stay connected, and it is the only control a teammate obeys.
- `tests/mcp-no-inherit.bats` — 8 tests, hermetic by default, plus an opt-in LIVE arm
  (`CC_MCP_LIVE_PROBE=1`) that runs a real `claude -p` against the fake server and asserts the unflagged
  control spawns BEFORE asserting the flagged one does not. A mutant run (`CC_MCP_NOINHERIT=off`) kills
  4 of the 8, so the guards are not vacuous.

**Real-fire verification — an A/B, because one arm alone proves nothing.** Two live `handoff-fire.sh`
fires of the same brief into the same worktree, which carried a project `.mcp.json` declaring the fake
logging server:

| fire | engaged | project stdio servers started |
|---|---|---|
| `--with-mcp` (the pre-change command shape) | yes, latency 169 s | **1** — parent recorded as the fired session's own `claude … --effort high You are a one-shot evidence…` |
| default (no-inherit) | yes, latency 16 s | **0** |

The fired session's own report closes it from the inside: its argv carried
`--strict-mcp-config --mcp-config=/…/cc-mcp-userscope-.claude-quaternary.json`, and `pgrep -P $PPID -l`
returned exactly one child — `caffeinate`. No MCP child.

⚠️ **The first attempt at this evidence FAILED THE FIRE, and that is the finding worth keeping.** It died
at `Invalid MCP configuration: Failed to read file: ENAMETOOLONG` with the pane left at a shell: the
composer had emitted `--mcp-config <path>`, and the option is variadic, so it consumed the brief — a bare
positional in every interactive launch — as a second config path. Nine green tests and every free probe
missed it because they all drive the CLI with `-p`, where the prompt is the value of a flag and can never
be slurped: **the shape under test did not contain the failing axis.** Fixed to `--mcp-config=<path>`
(`f32ba1f0`), now pinned both at the composer and by grepping the dry run's typed command line, which is
the only place a loose positional exists. (A second fire also failed to engage, before the control fire
engaged at 169 s on a box at load 13/10 cores — that one is the known INC-4 cold-fire race, not this
change; the treatment fire engaged in 16 s with the flags present.)

**Sites deliberately NOT changed** (a silent cap reads as coverage):
- `hooks/session-start.sh:74` — `claude mcp list`, a flagless child CLI that health-starts every approved
  stdio server on every session start, then exits. It is a spawn site and it was previously unnamed, but
  its whole purpose is counting connected servers, so `--strict-mcp-config` would make it report 0 forever.
  It belongs to W4's `aac347ddc003` (the probe is inert anyway — bare `command -v claude`). Its START lines
  are why the bats live arm attributes by parent argv instead of counting.
- `boot-resume.sh` · `lead-supervisor.sh` · `lr-handoff.sh` · `lr-reset-poller.sh` · `land-lock.sh` ·
  `cloud-ceiling-probe.sh` · `cc-reaper` · `cc-offload` · `cc-resume-resolve` · `cc-backlog` ·
  `cc-reconcile` · `cc-cloud` · `cc-relogin` · `claude-accounts` — enumerated from the brief's starting
  list and re-greped; their `claude -p` occurrences are all PROSE (comments, help text, printf fixtures),
  not live call sites. Nothing to flag.

## W4 · enforcement/accounting (backlogs `819839ed24b3` · `ef28f9bb11e6` · `e3fb627bc57a` · `aac347ddc003`)

**The riskiest wave — a SIGSTOP actuator's selection predicate.** All file:line refs verified 2026-08-10
(`03-enforcement.md`).

1. **fnm-space blindness (`819839ed24b3`):** `compressor-sentinel.sh:303-312` (census) + `:328-342`
   (`select_stop_targets`) + `cc-ignition-gate:182-183` (burst term) basename a whitespace-split comm field —
   fnm's `Application Support` path ⇒ every npx/fnm node reads as `Application`, census n=0 in 12,105/55,631 rows,
   actuator blind to the storms it exists to freeze. Fix: reassemble the FULL comm string before basename
   (the census agent's own working awk pattern is in `01-census-trees.md` §7.5 — spaces split fields, so rebuild
   from field N to NF). **In the SAME diff:** the `/mcp/` substring exclusions at `:336` and `:385` become a
   class test (`args ~ /(^|[/ _-])mcp([-_/ @]|$)|modelcontextprotocol/`) — fixing the census RE-ARMS the actuator
   against processes the spelling-exclusion no longer covers (B.3 hazard); tests must include (a) a positive
   control storm fixture the fixed census COUNTS, (b) an mcp-named process the selector still EXCLUDES,
   (c) an fnm-path node the selector now SEES. Same fix pattern in `cc-ignition-gate`.
2. **PER_MB tree derivation (`ef28f9bb11e6`):** `capacity-alarm.sh:1065` derives from session ROOTS
   (`:607-623` expression) — measured 616 MB root vs 681 MB tree. Add descendant-tree RSS to the constant's
   derivation (the coalition walk at `:707-727` already has the ppid-walk pattern to reuse; one derivation,
   not a third copy).
3. **coldcompile wire-or-retire (`e3fb627bc57a`):** registered in NO settings.json (2 hand-test rows ever).
   DECIDE: wire via a `c10` migration per `migrations/README.md` (the activation-queue convention) or retire the
   arm (git rm + doc note). The research leans wire-it (the burst gate is the missing admission arm) — but the
   wave session should read `docs/plans/MACHINE_CAPACITY_V2.md`'s current state first; capacity governance may
   have superseded it.
4. **Inert MCP probe (`aac347ddc003`):** `hooks/session-start.sh:61` uses bare `command -v claude` on the hook
   PATH → CONNECTED_COUNT always 0. Fix the resolution (the fleet pattern: `ps -o command= -p $PPID` / explicit
   binary path), or delete the probe if its consumer is gone (grep consumers first — `lookup-miss ≠ absence`).

**Verification:** bats suites for 1-2 green (with the positive controls); `bash scripts/compressor-sentinel.sh`
one census tick printed showing real node count; capacity-alarm one tick showing tree-derived PER_MB; migration
staged (if wired) shown in `deploy-migrations` output. **DoD:** four items closed with evidence.
**Constraint:** the actuator change ships OBSERVE-FIRST if any doubt — census fix immediately, actuator
target-selection behind one tick of logged would-reap before arming (the devserver-gc precedent).

## W5 · end-state verification sweep (lead-inline)

1. Re-run the census one-liner fleet-wide: expected zero unrequested chains; whatever chains exist are pinned,
   telemetry-less, heap-capped, opt-in.
2. `wrap-ledger`/`deploy-live` cycle green; the live layer carries the W3/W4 script changes (this repo IS the
   live source — new files need the converger; check `LIVE_ADDS`).
3. Close each backlog id (`cc-backlog done <id> --evidence <sha+verification>`); update this plan's wave sections
   to COMPACT form (learnings + shas); update `docs/research/mcp-memory-groundup-2026-08-10.md` §6 table rows
   from "filed" to "done (sha)". Append `Scope (grown)` lines for anything the waves surfaced.
4. 2.1.221 adoption (MCP discovery cache — the down-daemon failure-posture change) stays OUT of these waves:
   it is a fleet binary bump owned by the `cc-version-audit` process; file/refresh a backlog item if not present.

---

## Standing constraints (all waves)

- Landing: each repo's OWN `/ship`/policy, read live (this repo: project-local `/ship` from a dedicated worktree,
  never the shared checkout; reso: read its CLAUDE.md + `land-status.sh` at execution time).
- Config files (`~/.claude*.json`, settings) are LIVE multi-writer state: single-owner-per-file per wave,
  jq + atomic mv, never concurrent hand-edits.
- The research doc is the evidence SSOT — waves cite it rather than re-measuring, EXCEPT where a wave's own
  verification demands a fresh read (census counts, config states — perishable).
- Every wave ends with its verification commands RUN AND PRINTED (the goal evaluator sees only what a session
  surfaces), its backlog id closed with evidence, and a one-line report back to the lead.

## Why (decisions carried from the research — do not relitigate without new evidence)

- **No shared daemon**: five measured grounds (global toolMutex serialization; one-browser-per-process +
  profile lock; activity-leak concentration; cloud-lane cliff + localhost attack surface; >6.05 s restart-strand
  on ≤2.1.220). Revisit ONLY on: a genuinely concurrency-safe fleet-universal server AND ≥2.1.221 AND the
  `mcp-proxy` + launchd recipe in `06-daemon-multiplex.md` §5.
- **Deferral is not a memory lever** (tokens only — probe-proven); **consolidation is not compressor relief**
  (0.39% of one arm). The levers are scope, wrappers, lifecycle bounds, inheritance, accounting.
- **Aggregate ÷ N ≠ marginal** — any future MCP number cited in budgets must carry its generating command +
  population + attribution (memory: `aggregate-ratio-is-not-a-marginal`).
