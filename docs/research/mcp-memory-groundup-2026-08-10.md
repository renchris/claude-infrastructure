# MCP per-session memory — the ground-up optimal, measured (2026-08-10)

**Question (operator /goal):** the fleet's stated bottleneck model says ~340 MB per resident session
plus **"~507 MB of MCP server children that no budget counted"** caps this 64 GB box near ~100
resident sessions; 150+ requires "MCP consolidation". Investigate the 100th-percentile ground-up
optimal solution for per-session MCP memory — are we already at absolute perfection?

**Method:** 9-agent research wave (live census with full process trees · number provenance ·
enforcement-layer audit · spawn-semantics probe · CC client transport measurement · daemon/bridge
lab · per-server verdicts · scored design space · Fable adversarial premise-refuter), artifacts in
`docs/research/mcp-memory-groundup-2026-08-10/01…09-*.md`. Load-bearing citations spot-verified
against the primary sources by the lead.

---

## 1 · Verdict

**We are not at perfection — but the gap is not the one the goal names, and the named remedy
(consolidate MCP into a shared daemon) is measured HARMFUL, not optimal.**

1. **The premise number is refuted.** "~507 MB/session" was an aggregate misread as a marginal:
   `ps -A` RSS summed over 22 processes and divided by 10 sessions, with no ppid attribution, in the
   instrument the same wave's sibling axis had banned for a 3.3× shared-library double-count
   (`02-provenance.md` §1-2; origin `docs/research/scaling-bottlenecks-2026-08-09/08-platform-terms.md:96-97`).
   The corpus itself re-measured it 8× down the next day
   (`docs/research/memory-econ-rearchitecture-2026-08-10/census-fleet.md:379-401`), and this wave's
   own tree-walking census (`01-census-trees.md`) confirms a third consecutive timepoint:
   **MCP costs 0 bytes in ~85-90% of resident sessions; the whole MCP class is ~1.0-1.6 GB
   (1.4-2.5% of the box) concentrated in 3 `chrome-devtools-mcp` chains, all in reso worktrees.**
2. **Even zeroing MCP entirely moves the 150-session RESIDENCY math by ~5-10 GB** — real, worth
   taking, but 10-19% of the session cost and not the binding constraint (`09-adversarial-premise.md`
   SUSTAINED; sessions at 150 ≈ 37-53 GB footprint; the killers on record are burst ramps and
   compressor-segment structure). **MCP's second face IS inside that killer, though** (red-team D3):
   the 08-09 panic window's 2,248 MB × 4 renderers were puppeteer under chrome-devtools-mcp
   (`census-fleet.md:417-419`), the one observed renderer swings 52→412 MB peak, and a 12-member
   wave in a reso worktree ignites ~13 chains ≈ 4 GB — browser cost is an admission-gateable EVENT,
   not a residency. The adopted remedies (no-inherit, opt-in scoping, `--browserUrl` attach, heap
   cap) are chosen precisely because they kill this burst face too, not only the resident bytes.
3. **The 100th-percentile end-state is ZERO-ENTRY, not consolidation**: no `.mcp.json`/`mcpServers`
   stdio entry for the dominant capability at all (browser work rides the already-running shared
   CDP endpoint via `agent-browser`/`dia-agent`), an out-of-band session-manager for anything that
   genuinely needs MCP semantics, remote HTTP for what has a hosted equivalent — plus four free
   wins that hold under every design and a set of accounting fixes so this number can never be
   mis-derived again. That reaches the true floor — **0 bytes AND 0 context tokens per session** —
   with zero new daemons, ports, or attack surface (`08-design-space.md` §4, §7).
4. **The shared-daemon design the goal implies is rejected on five independent measured grounds**
   (§5 below) — the strongest: `chrome-devtools-mcp` serialises every tool call behind one
   process-global mutex and binds ONE browser per process, so a fleet daemon converts per-session
   isolation into fleet-wide serialisation, silent cross-session page contamination, and one
   concentrated OOM (`06-daemon-multiplex.md` §3.3, §7; `07-server-verdicts.md` "Why NOT
   daemonize-shared").
5. **What actually stands between today and the optimum** is five concrete defects: a stdio stanza
   that taxes every reso session eagerly for tools 3% of transcripts use; ~200 MB/chain of pure
   wrapper+telemetry overhead; teammate processes bootstrapping their own chains in MCP-configured
   worktrees (fan-out multiplier); an enforcement layer blind to MCP bytes (and — bigger — blind to
   the fnm-node storms its SIGSTOP actuator exists to stop); and three stale oracles still steering
   toward the refuted 507/consolidate remedy.

---

## 2 · The corrected numbers

| Quantity | Refuted claim | Measured (this wave, 2026-08-10/11) | Source |
|---|---|---|---|
| MCP per resident session | ~507 MB, universal | **0 B for 16 of 19 sessions**; ~64 MB amortized | `01` §Verdict; denominator by argv[0], never `pgrep -f` (which reads 283 vs a true 19) |
| Per HOSTING session | — | ~280-340 MB footprint/chain (3 node procs), **bimodal +196-470 MB when a browser actually launches** (lazy) | `01` §1, `08` §0 |
| Whole MCP class, box-wide | ~5 GB | **1,213 MB phys_footprint / ~945 MB true RAM** (compressor-corrected; RSS overstates Chrome 3× and understates idle chains — a 23h chain reads RSS 141 MB but 322 MB footprint, 91% compressed) | `01` §2, §6 |
| Hosting share | 10/10 sessions | **3/19 sessions (15.8%)** this census; the corpus's 12% (4/33) and the design census's 9% (3/32) divide by a MIXED population (sessions + `--agent-id` teammates — red-team D2), so the session-only share is **~16-20%** — all reso-cwd; a config fact, not a per-session constant | `01` §3, `census-fleet.md:387-392`, `08` §0 |
| At 150 sessions | ~49 GB ("forecloses 150-resident") | **~5-10 GB** at a session-only 16-20% hosting share | `01` §8, `census-fleet.md:399`, red-team D2 |
| Session base | "340 MB/session" | 340 MB is the paired-differential ARRIVAL marginal (sound, not an MCP number); process footprint measured **249 MB mean (227-267, n=13, `08`) and 353 MB mean (267-442, n=5, `01`) the same night** — non-overlapping samples, so carry the spread, not a blend (red-team D2); RSS ≈ 610-812 MB misleads | `02` §1, `08` §9.6, `01` §8 |
| Growth direction | assumed up | **RSS decays with idle** (compressor migration); growth tracks ACTIVITY not age — vendor leaks #2431/#2456/#2291 are per-active-session (~13 MiB/min), #2291 still open, and our call mix (51% `evaluate_script`, 316 screenshots) is exactly its load shape | `01` §6, `07` §"4× spread" |
| Orphans | — | 0 at census (one earlier 76%-of-class leaked pid, and 3 orphaned bridge wrappers from a prior lab, both since gone) — a watchdog concern, not a design constraint | `01` §5, `07` adjacent, `08` §9.7 |

**Instrument law (recurring, now thrice-proven in this corpus):** `ps` RSS is unusable for this
question in either direction; only `phys_footprint` + compressed-split answers "what does this
cost"; any `grep`-shaped census inflates by matching agent-brief argv (naive grep: 20 procs/6.45 GB
vs true 9/1.3 GB — `09` fact 2).

---

## 3 · Mechanism map — why the cost is what it is

- **Config topology (the entire cost driver).** All live sessions run under `.claude-next/
  -secondary/-tertiary/-quaternary` config dirs whose user scopes carry only `motion`/`motion-plus`
  (**remote HTTPS ⇒ 0 local processes, 0 held sockets** — measured: 99 established claude.exe
  sockets, none to mcp.motion.dev, because the server 405s the GET stream; `05` §5). The ONLY live
  stdio server is `chrome-devtools` from `reso-management-app/.mcp.json`, **inherited by ~79
  worktree copies** — one tracked file sets the marginal cost of every session that cds into a reso
  worktree (`08` §0). `browsermcp` sits user-scope in `~/.claude.json`, which **no fleet session
  reads** — live-but-orphaned config, not lazy loading (`01` §4).
- **Spawn semantics — now probe-proven (`04`, delivered post-land; controlled fake-server probes).**
  A stdio server in scope spawns **550-822 ms after launch, before the first model turn, on BOTH
  2.1.220 and 2.1.114** — `initialize` + `tools/list` complete in the same window whether or not the
  prompt ever mentions the tool (`04` Runs A/B/H; corroborates `01` §4's live observation); no
  lazy-stdio path exists (feature requests #26666/#38365/#18497/#13805 open; the 221+ discovery
  cache is remote-only). Spawn is independent of handshake success (a server that never answers
  `initialize` still spawns; the session proceeds past it as `pending` — startup never blocks).
  The **browser** is the lazy half (+196-470 MB on first browser tool call). Tool-schema deferral
  moves **tokens only** — measured: the process, handshake, and full tool list are paid ~10 s before
  the model fetches one schema (`04` §6). **The sharpest operational edge is the headless approval
  BYPASS** (`04` Runs E/E2 + docs-verbatim): `-p`/SDK/cloud sessions start **every** project
  `.mcp.json` stdio server, *approval list irrelevant* — even servers absent from
  `enabledMcpjsonServers` spawn; the only mode-independent block is `disabledMcpjsonServers`, the
  per-fire controls are `--strict-mcp-config`/`--setting-sources`. So every wave-fired headless
  session in a reso worktree pays unconditionally. Also measured: orderly exit tears servers down
  (SIGINT → +100 ms SIGTERM → SIGKILL — **a wild orphan MCP process therefore indicts a crashed
  session, never a clean exit**), and a stdio server that dies mid-session is NEVER auto-reconnected
  (HTTP/SSE are) — one more axis where stdio loses to the remote shape.
- **The fan-out multiplier.** In-process Task subagents share the parent's MCP clients and add no
  process — now **probe-proven**, not just observed: `04` Run G shows exactly one server process for
  the whole run, with the subagent's `tools/call` flowing through the parent's single client.
  **Separate-process teammates (`claude.exe --agent-id`) bootstrap from their cwd like any
  session** — observed live in the corpus hosting a full 4-process stack (`census-fleet.md:400`),
  and mechanically implied by the headless loading rule (`04` §4 E/E2: headless processes load
  project scope unconditionally); today's 13 teammates showed zero only because they all sat in
  MCP-free cwds (`04` §8.3 correctly marks its own teammate probe as the one unmeasured slot — the
  corpus observation stands). A 12-member wave in a reso worktree ≈ 13 chains ≈ 4.0 GB
  (`session-cost.md:111`). This is a *fan-out* cost, not a resident cost — and it is the second
  real MCP lever.
- **Enforcement blindness (audited at file:line, `03` §A-B).** The goal's "no budget counted" is
  half-true: MCP process COUNT is counted (capacity-alarm coalition rung — the one tree-aware
  term); MCP BYTES are counted by nothing that can attribute or act. `PER_MB=636` derives from
  session ROOTS only (true tree ≈ 681 MB/session today), so "room for ≥N more sessions"
  over-promises. Two instruments are inert for non-MCP reasons: the compressor-sentinel census +
  SIGSTOP actuator and the ignition-gate burst term all basename a whitespace-split comm — and this
  fleet's fnm node path contains a space, so they read **0 against 3 live node procs** (12,105 of
  55,631 log rows read n=0) — **the actuator is structurally blind to the exact dev-server storms
  it exists to freeze**. `coldcompile-admit.sh` is registered in no settings.json (2 hand-test rows
  ever). The `/mcp/` argv exclusion is a spelling, not a class. No gate anywhere admits on any
  count, resident or active; the single integration point is `cc_capacity_admit()` (all three spawn
  surfaces).
- **Client transport facts that shape the design (`05`, all measured on 2.1.220).** HTTP servers
  are serviced in-process (0 children, incl. subagents); startup is non-blocking (+0.22 s for a
  hung daemon); the startup retry ladder is 500/1500/4000 ms then **failed for the whole session**
  (a >6.05 s daemon restart permanently strands every session that started inside it; headless has
  no `/mcp` retry); `alwaysLoad` is the only blocking path (5 s cap); monitor
  `mcp_servers[].status`, not `mcp_server_errors` (stays `null` on real failures); ≥2.1.221's
  discovery cache flips down-at-start from "tools lost" to "cached, dial on first use" — the
  highest-leverage client-side change if any daemon is ever adopted.

---

## 4 · The design space and the floor

Eight architectures scored on marginal MB/session · fixed MB · latency · blast radius · isolation ·
ops · token cost · migration (`08` §2). The floor, numerically (`08` §4):

| Design class | Irreducible per-session cost | Reaches floor? |
|---|---|---|
| **No MCP entry** (CLI/skills vs shared CDP endpoint; out-of-band session manager) | **0 B, 0 tokens** | **YES — the floor** |
| `http` entry, schemas deferred | ~20 KB socket-state, ~83-165 tok (server-authored, negotiable to ≈tool-names) | near-floor on bytes; permanent token tax |
| Any stdio entry | ≥99 MB (smallest measured server), 339 MB the real one, +116 MB via npx | off by 10⁴ |

External prior art says nobody ships this for us: upstream "share MCP across sessions" closed
duplicate (#28860), the identical-hardware kernel-panic report closed not-planned (#45880 — M1 Max
64 GB, 15 sessions × 34 servers → 308 node procs → panic), lazy-stdio requests open and unshipped.
Off-the-shelf pieces exist where needed: `mcp-proxy` (the one bridge that genuinely multiplexes one
child — lab-verified; supergateway spawns per-session/per-request and its SSE mode broadcasts
cross-session), `mcp-on-demand` (the B2 shape), agentgateway (5-20 MB Rust front door)
(`06` §4, `08` §5).

---

## 5 · The chosen end-state — and what was rejected

### Adopted (the 100th-percentile shape)

1. **H — make the stdio stanza opt-in instead of eager-everywhere.** Today `chrome-devtools` in
   `reso-management-app/.mcp.json` (one stanza × 79 worktrees) taxes EVERY reso session ~280-340 MB
   at start for tools 3.2% of transcripts use. End-state: sessions that verify browsers opt in
   (per-session `--mcp-config`, or a `.mcp.json` kept only where the verification workflow lives),
   with `--browserUrl` attaching to the already-listening shared browser (`127.0.0.1:9222`) instead
   of owning one — that flag alone removes the +196-470 MB browser even where the server stays —
   and everything else rides the existing non-MCP paths (`agent-browser` CLI — 67 transcripts
   already use it; `dia-agent`/CDP). Marginal cost for non-opting sessions: **hard 0 B + 0 tokens.**
   **This overrides `07`'s "KEEP-SCOPED — lifecycle unchanged" deliberately, and the adjudication
   is** (red-team D1): `07` judged project-scope CORRECT *relative to user-scope and daemonizing* —
   true — but its own usage table shows the invoking dirs are ~24 scattered ephemeral worktrees, so
   "the project dirs that need it" has no stable boundary short of opt-in; eager-in-79-worktrees is
   the measured tax. The capability is NOT deleted (usage is hot — 2,384 calls/30 d): **sequencing
   is free-wins-first** — the npx drop + telemetry kill + heap cap recover ~60% of each chain with
   zero workflow change — **and the stanza flip is gated on the reso owner confirming CLI/CDP or
   opt-in parity for the measured call mix** (51% `evaluate_script`, screenshots, traces), which is
   exactly what backlog `572b6341aa12` requires before it closes.
2. **B2 for genuine MCP-semantics needs** — an out-of-band session manager (mcp-on-demand pattern,
   idle-exit added) owning stdio children; CC never learns the server exists ⇒ 0 tokens, 0 resident
   when unused. Optional; nothing today strictly requires it.
3. **browsermcp: eliminate everywhere it is configured.** 0 invocations in 3,504 transcripts/30 d;
   upstream frozen since 2025-04; architecturally single-instance (hardcoded port 9009, each new
   instance `kill -9`s the incumbent — per-session spawning was never valid; `07` §B5). Capability
   already covered twice over. Cleanup sites enumerated in `07` (user-scope key, 2×
   `enabledMcpjsonServers`, 4 project settings, 1 project declaration).
4. **Free wins under every design (`08` §8, `07`, `session-cost.md` G1-G4):** drop `npx`/`npm exec`
   from any surviving stdio entry (kills a 71-156 MB resident wrapper — 21-35% of each chain — and
   the per-spawn registry roll that had 1.6.0 and 1.7.0 running side-by-side; pin the version);
   `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1` (kills the ~88-110 MB/chain telemetry watchdog);
   `NODE_OPTIONS=--max-old-space-size` per entry (bounds the open leak #2291's blast); never
   `alwaysLoad`; recycle long-lived heavy-verification servers (leak is per-activity); reclaim the
   1.3 GB dead persistent Chrome profile; reconcile the conflicting non-`--isolated` duplicate
   config (`07` §C4).
5. **No-inherit for agent fan-out** — teammates/subagents spawned for research/implementation in
   MCP-configured worktrees should not bootstrap browser MCP (a research-agent profile without it,
   or spawn-time `--strict-mcp-config`); kills the 13-chains-per-wave multiplier
   (`census-fleet.md:400`, `orchestration-econ.md:136`).
6. **Accounting so this stays true (`03` §E-F):** derive `PER_MB` from process TREES; add the MCP
   row to the S6.2 budget with the measured constants; count-admission hooks into
   `cc_capacity_admit()` (the one shared predicate) if adopted; if any daemon is ever built, add
   the launchd-rooted argv-table term (a daemon re-parents out of the coalition walk — the only
   count that sees MCP today would silently read *healthier* on consolidation) and record absence
   as `null`, never 0. Fix the always-skipped MCP connectivity probe (`session-start.sh:61`,
   backlog `aac347ddc003`).

### Rejected: the always-on shared daemon ("MCP consolidation" as originally scoped)

Five independent measured grounds (`06` §3.3/§7/§9, `07`, `08` §6-7, `05` §3c):

1. `chrome-devtools-mcp` holds a **process-global tool mutex** — one daemon = one serial queue for
   all N sessions (structural; no flag) — and a process-global selected-page (cross-session
   hijack; upstream fix experimental).
2. **One browser per process** (upstream #926 open) + exclusive profile lock; the vendor's own
   concurrency answer is `--isolated` per session, i.e. the opposite of sharing.
3. The known **activity-proportional leak concentrates**: N sessions × ~13 MiB/min into one heap =
   one fleet-wide OOM instead of N bounded ones.
4. **Cloud-lane degradation**: spilled sessions cannot reach `127.0.0.1` — only REMOTE MCP (and
   zero-entry sessions that never needed the capability) keep the spill boundary invisible; a
   local-CDP path cliffs off-box too, so browser-verification work stays on-box under every local
   design (red-team minor, `08` §6). A daemon additionally adds an unauthenticated localhost
   attack surface (both bridges bind `*:port` by default with permissive CORS) that stdio
   structurally lacks.
5. **The restart trap**: >6.05 s of daemon downtime permanently strands every session that started
   inside it (no post-ladder retry on ≤2.1.220; headless has no manual reconnect).
   Compressor-relief is not a justification either: consolidating today's chains recovers **0.39%
   of one trip arm that cannot fire alone** (`03` §D).

If a shared daemon is ever justified (a genuinely concurrency-safe, fleet-universal server), the
verified recipe is on file: `mcp-proxy` (the only true multiplexer) + launchd `KeepAlive` +
`ProcessType Interactive` + fd 8192 + 405-on-GET + `--host 127.0.0.1` + `--apiKey` + no
`alwaysLoad` + ≥2.1.221 first (`06` §5, `05` §8).

---

## 6 · Implementation path

**Done this session (this repo):** this synthesis + the 9 artifacts committed under
`docs/research/mcp-memory-groundup-2026-08-10/`; `docs/plans/CONCURRENCY_PROGRAM.md` S6.2 gets the
MCP row with the corrected constants (the budget that owned the defective number);
`docs/research/memory-econ-rearchitecture-2026-08-10.md` T2.7 carries the 507→62/140/325
correction pointer; backlog `1ab1d8b66098` re-titled off the refuted number/remedy; findings filed
to their owning surfaces (below).

**Filed, not reached across (owners elsewhere or risk-bearing):**

| Item | Owner/surface | Why filed rather than done here |
|---|---|---|
| Remove `chrome-devtools` stanza from `reso-management-app/.mcp.json` (×79 worktrees) or gate it to the QA dirs; add `--browserUrl` opt-in shape | reso repo | Another repo's tracked file; needs reso's verification-workflow owner to confirm CLI/CDP parity for traces/network inspection (`08` §7 residual) |
| Drop npx + pin + `NO_USAGE_STATISTICS` + heap cap in surviving entries | reso repo (`.mcp.json`, `scripts/mcp/chrome-devtools-mcp.sh`) | Same file ownership |
| Delete browsermcp config + stale summoners (6 sites) | `~/.claude.json` + settings files | Live cross-account config; trivial but touches the primary account's file this fleet doesn't read — batch with the reso pass |
| fnm-space comm fix in `compressor-sentinel.sh` census + actuator and `cc-ignition-gate` | this repo, own change | Re-arms a SIGSTOP hazard by design (`03` §B.3): needs the class-test exclusion + tests in the same diff — a safety-actuator change, not a config flip |
| Register `coldcompile-admit.sh` (or retire the arm) | this repo, c10 migration | Activation-queue convention: new wiring lands as a migration |
| Teammate/subagent no-inherit profile | this repo (spawn surfaces) | Design choice touching agent-teams machinery; T9.1 already names it |
| ≥2.1.221 adoption for the discovery cache | fleet binary track | Version-gate process (`cc-version-audit`) owns binary bumps |

## 7 · Wave-internal conflicts, adjudicated

- **"Subagents spawn no MCP" (`01` §5) vs "subagents inherit and spawn their own" (corpus):** both
  correct — Task subagents are in-process (share clients); `claude.exe --agent-id` teammates are
  separate processes that bootstrap from their cwd; today's teammates all sat in MCP-free cwds.
  The multiplier is real for teammates in MCP-configured worktrees.
- **"Shared daemon is a precondition" (`06` §1) vs "keep-scoped" (`07`, `08`):** `06`'s verdict
  extrapolated fleet-wide hosting, which every census refutes (9-16%); its own adversarial pass
  (§9.8) concedes scoping+npx-removal wins at observed penetration. Its mechanical findings all
  argue against its own headline.
- **"4× growth over age" (lead's scout framing) → refuted:** activity-driven, not time-driven; the
  oldest chain is the smallest (`07`).
- **Config-dir premise (lead's scout + brief):** user-scope browsermcp in `~/.claude.json` was
  real but irrelevant — no fleet session reads that file (`01` §3-4, `08` §9.5). The migration
  target is the repo-checked `.mcp.json` files and the `.claude-*` config dirs.

## 7b · Red-team disposition (wave 2)

A Fable red-team ran against this synthesis after it was drafted
(`mcp-memory-groundup-2026-08-10/10-redteam-synthesis.md`): **DENTS — no core claim breaks.** Its
fleet-mix attack (would reso-dominance revive the daemon?) FAILS on the daemon's own serial-queue
arithmetic — more hosting makes the daemon worse while zero-entry is share-invariant. The three
surviving dents are folded in above: the explicit `07`-vs-H adjudication + free-wins-first
sequencing (§5.1), the mixed-population denominator correction (9-16% → session-only 16-20%,
at-150 5-10 GB, footprint spread kept unblended — §2), and the burst-face naming (§1.2). The minor
spill-invisibility wording in rejection ground 4 is corrected.

## 8 · OPEN / uncertainties (named)

- ~~`04-spawn-semantics.md` pending~~ — **DELIVERED post-land and integrated** (§3 rewritten from
  its probes): fully corroborative on eager/no-lazy/deferral-is-tokens-only, plus the headless
  approval bypass and the measured teardown ladder. Its one named gap: a teammate process in a
  stdio-configured repo was not probed directly (the corpus's observed instance +
  the headless loading rule carry that claim; one paid teammate-in-reso probe would close it).
- Whether 2.1.221's discovery cache eliminates the startup *connection* or only the wait (`08`
  §11); moot for zero-entry, decisive for any future daemon.
- The hosting share (9-16%) is a work-in-flight snapshot, entirely cwd-determined; a reso-heavy
  wave moves it linearly — which is precisely why the fix is the stanza, not the fleet.
- 340 MB arrival-marginal vs MCP-tree overlap (≤180 s differential window vs 53 s chain spawn) is
  unresolved in the corpus (`02` §2.3); does not change any conclusion here (both terms shrink
  under the adopted design) but the S6.2 row must not double-bill them.
- Single-timepoint censuses (3 same-day instruments agree; still one day). The leak class
  (footprint peak 3,213 MB, zero browsers) has no named trigger yet — bounded by the heap-cap +
  recycle policy rather than root-caused.
