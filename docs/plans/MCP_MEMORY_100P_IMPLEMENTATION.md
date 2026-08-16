---
status: complete
---

<!-- COMPLETE 2026-08-15. W5 (2026-08-11) closed all seven ids with real shas and recorded exactly
     one thing outstanding: "the program is LANDED, and NOT LIVE for one shared reason" — the
     bootstrap circle in which ~/.claude/scripts/postland-verify.sh symlinked into a shared checkout
     that was behind trunk, so the LIVE runner was the pre-C29 one, kept false-redding, and no green
     stamp could ever appear for deploy-live to advance to.

     That circle is BROKEN. The operator reset the shared checkout to origin/main (2026-08-15); it
     now reads 0 behind / 0 ahead, the live postland-verify.sh is byte-identical to trunk, and
     deploy-live reports "at trunk tip — nothing above the live layer to deploy". The inertness this
     plan named as its proof is gone: ~/.claude/scripts/compressor-sentinel.sh greps 6 for
     `exe_table` where W5 measured 0 live against 6 on trunk. Both downstream rows (3df911c0470e,
     b3093462ed6c) are done.

     Flipped because this frontmatter is the machine-readable SSOT scripts/find-plan.sh and every
     plan-open falsifier read — a finished plan left at `open` re-mints an "advance" row forever,
     which is exactly what CODEX_ADVERSARIAL_SLOT_PROBE.md did for four days. -->


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

### W1 + W2 — DONE 2026-08-11 (one session, as Phase 0 planned)

**Landed.** reso `f4eadb534` (free wins) + `e0e7c951a` (opt-in flip), both content-verified on
`origin/main` via reso's own `scripts/ship-land.sh` — `land-status.sh` asserted live that landing
bills nothing. claude-infrastructure `47cc3f27` (wrapper retirement), 7 paths content-verified.
Backlog `572b6341aa12` and `87ef04ead50d` closed with evidence.

**🚨 W1's stated premise was already false when this plan was written — check before briefing from
it again.** The plan (and the wave brief) recorded the stanza as
`chrome-devtools: npx chrome-devtools-mcp@latest --isolated`, "verified 2026-08-10". `origin/main`
had routed it through `scripts/mcp/chrome-devtools-mcp.sh` since **2026-08-06** (`7f3ffea02`). The
pre-grep read a lagging checkout — the exact trap reso's own `CLAUDE.md` documents ("local `main`
is a LAGGING CACHE — read `origin/main`"). The plan also expected the wrapper in "two worktrees";
it is on trunk, so it is in **all** of them. Nothing errored; the free wins simply had to be applied
inside the wrapper rather than to the stanza.

**The flip PASSED its evidence gate** (it was not forced):

- **Parity 11/11.** `agent-browser` was run — not name-matched — against a live reso preview route,
  one row per tool weighted by the real 30-day mix. The checklist needed two corrections before its
  result meant anything: `tab new` switches context (so the snapshot and click rows had been running
  against `about:blank`), and the click row asserted a regex that could not fail, reporting PASS over
  the literal text "Element not found". Final form counts click events the PAGE receives, with a
  bogus-selector negative control that must not increment.
- **Control A/B/A.** default → 2 processes (~188 MB + ~79 MB); `disabledMcpjsonServers` → none;
  setting removed again → chain returns. The third run is the point. Attribution walks UP each
  candidate's ppid chain — a global `ps | grep` on this box credited other sessions' chains to the
  probe.

**🔑 Two findings W3 should not have to rediscover:**

1. **A project-level disable BEATS a local enable, and it fails SILENTLY.**
   `enabledMcpjsonServers:["chrome-devtools"]` in a worktree `settings.local.json` spawned nothing
   against a project-level `disabledMcpjsonServers`. The working opt-in needs BOTH keys
   (`"disabledMcpjsonServers": []` as well). Documented in reso's `CLAUDE.md`; shipping the flip
   without it would have been shipping a trap. The asymmetry is also what makes disable-by-default
   safe — nothing can accidentally re-enable it.
2. **W2's site list was under-counted, in a way a name-grep finds and a path-grep does not.** Actual:
   **5** config dirs with `enabledMcpjsonServers` (plan said 2 + "mirrors"), **5** project
   `settings.local.json` (plan said 4), plus **60 dead `mcp__browsermcp__*` permissions** (12 × 5
   files) the plan did not mention at all, and `~/.claude/.mcp.json` is **one real file that 4
   config dirs symlink into**. Repo-side, the wrapper was named by **three copy-lists**
   (`install.sh`, `sync.sh`, `deploy-parity-assert.sh` `COPY_TOOLS`) — a parity list naming a file
   the repo no longer ships reports drift forever, which is how a guard stops being read.

**Known reach limit, stated not discovered later.** `.mcp.json` and `.claude/settings.json` are
tracked, so a worktree gets the free wins and the flip only once it **rebases**. At land time ~70 of
77 reso worktrees were on an older base and kept the eager `npx @latest` server; the live census
still shows their chains. Fleet-wide effect is a rebase question, not a landing question — W5's
sweep should count it that way rather than reading those chains as a failed flip.

**Also done under W1(d):** the dead 1.3 GB `~/.cache/chrome-devtools-mcp/chrome-profile` deleted,
after proving unreachability first — every chrome-devtools config on the box (77 worktrees + 2
checkouts) either passes `--isolated` or routes through the wrapper, which passes it on both exec
paths; the one config that did not was the `~/.claude.json` shadow entry, deleted the same day (1.e).

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

### W4 OUTCOME (2026-08-11) — item 1 landed `273df7cd`; item 3 decided, not deferred

**The root cause was not the one the wave was briefed on, and the brief's prescribed fix was right for
one site and wrong for three.** `ps` widens only its LAST column. The census (`pid=,ppid=,rss=,comm=`)
has comm last, so its value is COMPLETE and its spaces split — `$4` basenames to `Application` and the
row drops, exactly as briefed, and rebuilding `$4..NF` is exact there. But `select_stop_targets`,
`select_break_parents` and `cc-ignition-gate` put comm BEFORE `args=`, where **ps truncates it to a
fixed 16 characters** — `/Users/chrisren/`, `/Library/Applica`, `endpointsecurity`, all exactly 16,
measured live. There the basename was not split, it was **absent**: no real node install has a path
that short, so the cohort test could match nothing but a process whose comm was literally `node`.
argv[0] is no escape either — it carries the same spaced path and splits identically (measured: 0 hits).
A "rebuild the fields" there would have swallowed args.

comm-last and args-last cannot both hold in one read. The split: **args stays LAST** (every exclusion
sees a complete argv) · **ppid attribution stays in that one table** (what the old one-instant comment
was really protecting) · only the **name** comes from an adjacent comm-last read, via a new `exe_table`
that is now the single node-ness predicate for all three consumers. Lead-imposed conditions, all met:
the recycle hazard the second read opens is guarded by requiring the two tables to **agree on PPID**
(a pid reused between them must reproduce its predecessor's parent to get through), and
UNIDENTIFIABLE ⇒ NEVER ACTED ON in both directions.

🚨 **THE MOST TRANSFERABLE FINDING — a safety rail that had never once worked.** The actuator excluded
claude twice over "by construction": `base == "claude.exe" || base == "claude"` on the comm, and
`args ~ /claude/` on the argv. The comm half was **dead from the day it was written**, for the same
16-char truncation: `/Users/chrisren/.claude-next/local/node_modules/.bin/claude` reaches that test as
`/Users/chrisren/`, basename empty. **Only the argv test had ever protected an operator's session from
SIGSTOP**, and nothing could have revealed it, because the cohort test upstream was equally blind — the
predicate never reached a live process, so a redundant rail and an absent one were indistinguishable.
*The general form: a defence whose upstream selector is blind cannot be observed failing. Two rails
written for one hazard are one rail until something proves each of them fires on its own.* Repairing
the census re-armed all of it at once, which is why the class-test and the observe rung were
non-negotiable in the same diff.

**OBSERVE-FIRST, run on the live box before arming** (`CC_SENTINEL_ACT=observe`, a new rung — the one
this actuator lacked on 2026-08-09, when the only way to learn what the predicate would touch was to
arm it). Live plist values (floor 40960 kB, cap 400), `prev_census` deliberately EMPTY so every node
process counts as brand-new burst — the worst case:

```
### exe_table rows: 1261  · node-named: 4
WOULD-STOP: (none)
  pid=14588   excluded_by: mcp=MCP-CLASS   pid=49988   excluded_by: mcp=MCP-CLASS
  pid=85282   excluded_by: mcp=MCP-CLASS   pid=95588   excluded_by: mcp=MCP-CLASS
WOULD-STOP parent: (none)
### POSITIVE CONTROL — same live table plus ONE synthetic innocent node proc:
  WOULD-STOP pid=999001 900000 node
```

All four live node processes are MCP chains and all four are excluded; the positive control proves the
selector is live rather than inert, so "(none)" is the exclusion firing. The plist stays
`CC_SENTINEL_ACT=stop` — disarming a guard that exists to prevent kernel panics would be a protection
regression, and the observe tick is the evidence the brief asked for, not a mode to ship in.

**Item 3 — coldcompile: WIRE, and it is already wired as far as an agent may wire it. The open question
is a re-aim, not wire-or-retire.** `migrations/0006-coldcompile-admit-registration.sh` exists, is class
`c10`, and by design STAGES rather than executes — it files to `cc-backlog needs` (`f30fa039f98f`) and
waits on the one-time C10 rescope ratification (`b09f54e9e080`). `MACHINE_CAPACITY_V2.md` has NOT
superseded it: that plan is about Darwin QoS bands and never mentions ignition or cold compiles at all.
What HAS moved is more specific — decision packet `99637eaee7b9`, actioned by the operator 2026-08-10:
*"ratify all except the cold-compile hook, then ratify 0006 after the re-aim lands"*, with the re-aim
filed as `9362e80a999f` (the PreToolUse(Bash) chokepoint misses the Aug-9 storm shape: mass
invalidation of a long-lived `next-server` driven by fleet Edit/Write calls). So the research's
"leans wire-it" and the alternative "retire the arm" are both wrong: it is wire-after-re-aim, decided
one day after the research snapshot. `e3fb627bc57a` is closed as superseded by `9362e80a999f`.

🚨 **And the re-aim's premise now needs re-checking, because part of the gap it names was this wave's
bug.** The gate's TERM 2 — the burst census — exists precisely for that storm shape: an old
`next-server` whose etime is hours, which TERM 1's settle window can never match, so *"only the process
count tells"*. That count was **structurally 0**. Control on the live box, same instant, same fixture:

```
PRE-FIX : clear node_n=0        (origin/main cc-ignition-gate)
POST-FIX: clear node_n=4
```

The term built to catch the Aug-9 shape had never been able to count a single fnm- or homebrew-installed
node. How much of "the chokepoint misses that shape" was chokepoint PLACEMENT and how much was this
blindness is now an open question on `9362e80a999f`, and it should be answered before the re-aim is
designed — a re-aim scoped against a measurement taken through a dead instrument would be aimed at the
wrong thing.

**Item 2 — PER_MB tree derivation, landed `b5fa476a`.** The frozen 636 counted session tree ROOTS and
charged every descendant to nobody. Now derived live from whole-tree RSS, reusing
`read_coalition_procs`' existing parent[]/depth-64 walk — one walk in the file, asserted by a test so a
future caller cannot quietly fork it. Live tick: **865 MB/session (`per_session_mb_src":"derived"`,
17,303 MB over 20 trees), against the constant's 636** — i.e. the old figure overstated remaining
headroom by ~34% (41 more sessions, not the 55 the constant implied). Every state names its own source
(derived / override / fallback), because this file has already shipped the other version of that defect
twice (`${SWAP_MB:-0}` rendering a dead sysctl as a healthy 0; `"est_room_sessions":?` making the one
row that said "the instrument broke" the one row no JSON parser could read).

**Item 4 — inert MCP probe, landed `e3509eb6`, and the briefed root cause was wrong in the direction
that matters.** `command -v claude` did NOT fail on the hook's PATH: measured over
`~/.claude/logs/sessions.log`, **7,022 of 8,636 sessions logged an MCP Status line**. It resolved — to
`~/Library/pnpm/claude`, the stock pnpm install at **2.0.5**, while the session that fired the hook was
**2.1.220**. Side by side the same minute: stale binary 2 servers, running binary 6. The four
claude.ai session-connected servers were structurally invisible, and the sensor fed `MCP: 2 server(s)`
into every session's additionalContext as fact. *A "never ran" sensor is loud; a sensor answering
confidently from the wrong subject is not, and it had been doing so for 81% of all sessions.* The
resolution now ends at the PPID's own binary and deliberately has **no bare `command -v claude` rung**.
The second half: "could not ask" and "answered zero" no longer share one value.

⚠️ **Its cost, stated because W3 named it.** The probe still shells out to `claude mcp list`, so it
still spawns one MCP chain per session start — ~2.6 s median, 2.89 s worst on a clean bench. Accepted,
because the alternative (reading config) cannot answer a *connectivity* question at all, and because
this is strictly better than what it replaces: the old loop had **no ceiling whatsoever** (3 unbounded
CLI spawns + 3 s backoff), and the probe is now bounded twice, per-attempt and whole-probe. The bound
itself is a lesson: the first value written was 5 s and a live fixtured run refuted it **inside the
hour** at 10.5 s — a clean-bench median is not the band on a box also running sibling sessions and a
bats corpus.

**Wave verification (all run this turn):** `compressor-sentinel` 82/82 · `ignition-gate-census` 9/9 ·
`capacity-alarm-permb` 6/6 · `capacity-alarm` 37/37 (unchanged) · `session-start-mcp-probe` 14/14.
Every suite's control replays the REAL pre-fix artifact from `origin/main`, never a mutant of its own
test file. **Filed, not folded:** `09f087a7f3d8` — `scripts/terminal-bench.sh:167` carries the same
comm-split defect (`split($2,a,"/")` over a comm-LAST read), so an fnm-installed binary is never found
by name and the bench silently measures nothing; one-line fix, but it needs a fixture that does not
exist yet, which is why it did not join the frozen four.

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

### W5 OUTCOME (2026-08-11) — all seven ids closed; the program is LANDED, and NOT LIVE for one shared reason

**Ids, all `done` with real shas** (verified by re-reading the ledger, not by trusting the reports):
`572b6341aa12` reso `e0e7c951a` · `87ef04ead50d` `47cc3f27` · `eece54939e7f` `ff49e1e3..2b0977be` ·
`819839ed24b3` `24e30061` · `ef28f9bb11e6` `6df645dc` · `e3fb627bc57a` `e5312a26` (superseded, not
done-by-us) · `aac347ddc003` `49a6e466`. Reso's two land via reso's own rail (`land-status.sh`
asserted live that landing bills nothing there — read at execution time, never assumed from here).

**1 · Census (run + printed).** 13 `chrome-devtools`-family processes still alive fleet-wide.
**This is the reach limit, not a failed flip** — and the distinction is the finding. Tracked config
reaches a worktree only on REBASE, and ~70 of 77 reso worktrees sit on an older base still running
the eager `npx chrome-devtools-mcp@latest --isolated` chain. The landed shape is correct and proven:
stanza is `bash scripts/mcp/chrome-devtools-mcp.sh`, `disabledMcpjsonServers: ["chrome-devtools"]`,
and a `-p` probe plus interactive `mcp list` in a landed worktree both spawn ZERO. Read a live census
against a tracked-config change as a **rebase question**; a fleet number cannot falsify a per-tree fix.

**2 · Live layer — the one thing that is NOT done, and it is a bootstrap circle, not a lag.**
`deploy-live` refuses: *no GREEN tree is a DESCENDANT of live HEAD* — the newest green stamp is
BEHIND it. So the budget is not the binding constraint; there is **no eligible tree at all**, and
nothing landed since has converged. The circle (filed `3df911c0470e`, blocked, pre-existing and NOT
caused by these waves): `~/.claude/scripts/postland-verify.sh` symlinks into the shared checkout,
which is behind trunk, so the LIVE runner is the pre-C29 one → it keeps false-redding → no green
stamp can appear → the live layer never receives the fix that would stop the false reds.
Direct observation from three consecutive sweeps this session: two CUT by machine pressure (SIGTERM,
load 22 on 10 cores), one convicting `tests/cc-fleet.bats` in a single load window (C29 pending).
Consequence, measured: origin/main carries the W4 fixes while `$HOME/.claude/scripts/compressor-sentinel.sh`
still serves pre-fix bytes (`grep -c exe_table` → 6 on trunk, 0 live). **Net safety position is
unchanged and no worse** — the actuator keeps the predicate it has always had; the fix is landed,
content-verified, and inert. Breaking the circle needs a one-time forced advance past a fail-closed
gate — operator judgment, and a raw `ff` is explicitly NOT the move (`04470b5d` records that it
wedges deploy and resets both legs). Downstream and gated on it: `b3093462ed6c` (the sentinel daemon
is a long-running bash that parsed its loop once — pid 77490 — so even after the fast-forward the new
predicate is not armed until `launchctl kickstart -k gui/$UID/com.claude.compressor-sentinel`).

**4 · 2.1.221** filed as `c9787e610bca` (none existed).

**Scope (grown): +the goal-vs-background-Bash guard** (`0e021a9d68e3` → `d59dff44`), F1-F4 PASS,
surfaced BY this program rather than planned into it. The lead parked a `Bash(run_in_background)`
monitor to watch a fire; CC skips `/goal` evaluation at every Stop while any non-terminal background
Bash exists, so the goal driving this program never evaluated — measured **2 h / ~12 turns / 0
evaluations** — and 8 peer HANDOFF-PINGs waited for the operator to type across four round-trips.
Two defects, and the second is the durable one: (1) that monitor could never exit, because its
predicate matched only the SUCCESS token (`^→ fired:`) while the fire wrote `!! FIRE FAILED` — a
watcher that cannot observe the failure path parks forever; (2) **the guard was on one door only** —
`cc-await-ping` REFUSED to arm and said why, while a raw backgrounded Bash had no guard at all and
disabled the goal identically. Shipped as a DENY in `hooks/validate-bash.sh` keyed on SHAPE
(poll-loop / follow-tail / `sleep ≥120` / `cc-await-ping`, judged per command segment), because
duration is the real hazard but is unknowable at PreToolUse; 16/16 TAP with 5 red-proved against
pre-fix trunk and four passes-silently controls green on both trees. The standing memory
`goal-stop-hook-vs-task-registry` named only the cc-await-ping door and has been widened to the
mechanism. **Generalisable:** when two call paths reach one hazard, a guard on the ergonomic one is
not coverage — it is a signpost on the road nobody takes.

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
