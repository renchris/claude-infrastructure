---
status: closed
created: 2026-08-11
owner: desk
verdict: DO-NOT-MIGRATE
---

# jcode due diligence — does it address the 150-session bottleneck?

**Method.** 22 agents, 0 errors, 3.33M subagent tokens, 581 tool calls, ~27 min wall
(`wf_363ad50b-f2b`). Ten independent axes, each followed by a skeptic tasked to *refute* its
load-bearing claim, then a completeness critic, then this synthesis. Every axis ran read-only.
Per-axis evidence: [`jcode-due-diligence-2026-08-11/`](jcode-due-diligence-2026-08-11/).

**Provenance warning that should outlive this doc.** `WebFetch` on `https://jcode.sh/docs` returned a
description containing a phrase appearing **zero times** on that page and verbatim from the calling
agent's own system prompt — the summarizer substituted its context for the source. Every claim about
jcode here was re-verified by direct fetch plus grep. Treat `WebFetch` summaries of this project as
contaminated.

| Axis | Skeptic | Findings | Verdict |
|---|---|---|---|
| [`layer-identity`](jcode-due-diligence-2026-08-11/layer-identity.md) | REFUTED | 13 | jcode is an agent harness that runs INSIDE kitty exactly as `claude` does — it replaces the `claude` binary and nothing else, so "migrate from kitty t |
| [`cost-gate`](jcode-due-diligence-2026-08-11/cost-gate.md) | SURVIVED | 11 | jcode FAILS the cost gate, but on a worse axis than pi-claude did: its Anthropic path very likely does NOT bill outside the plan — it draws on plan qu |
| [`memory-claim`](jcode-due-diligence-2026-08-11/memory-claim.md) | REFUTED | 11 | The benchmark's headline (386.6 MB Claude Code, "13.9× more RAM") is an artifact of N=1 PSS accounting plus a non-default jcode config and should be d |
| [`mcp-term`](jcode-due-diligence-2026-08-11/mcp-term.md) | REFUTED | 10 | No on both halves: the MCP term is ~19-21% of resident cost (measured 1,050 MB total across the WHOLE box today, from exactly 3 sessions), not 60%, an |
| [`bottleneck-audit`](jcode-due-diligence-2026-08-11/bottleneck-audit.md) | REFUTED | 10 | Six of nine clauses survive with corrections and three do not — C2/C3/C4/C6/C7 hold as arithmetic, C5's number is right but its cause is a policy cons |
| [`coupling-census`](jcode-due-diligence-2026-08-11/coupling-census.md) | REFUTED | 13 | A jcode swap is not a binary change but a rewrite of this repo's control plane: 42% of the 81 wired hook commands survive with intact semantics, 32% w |
| [`shim-frame`](jcode-due-diligence-2026-08-11/shim-frame.md) | REFUTED | 9 | No — the frame is a layer error: jcode is a HARNESS (Claude Code's layer), not a terminal, so it can never be a third shim under kitty; and the consol |
| [`risk-maturity`](jcode-due-diligence-2026-08-11/risk-maturity.md) | REFUTED | 13 | No — jcode fails as a production dependency today on grounds that are independent of whether its RAM claims are true: its current release shipped 44 m |
| [`ranked-levers`](jcode-due-diligence-2026-08-11/ranked-levers.md) | REFUTED | 12 | Ranked by (gain × reversibility) / effort the order is L7 context-ceiling cap > L2 burst-bound/admission > L1 MCP consolidation > L6 idle eviction (bl |
| [`trial-design`](jcode-due-diligence-2026-08-11/trial-design.md) | REFUTED | 16 | README §6's instrument does NOT apply — jcode is a harness, not a terminal, so four of terminal-bench's five axes return NA by construction; the right |

---

# Decision memo — jcode

**Do not migrate: jcode's only plan-drawing Claude path buys headroom on the one axis this box's own instruments say is not binding, and pays for it by presenting our four Max subscriptions' OAuth tokens to Anthropic as if they came from Claude Code — while the three levers that *are* binding cost about one agent-day each and need no harness change. The one jcode action worth taking this week is a 90-minute local-model trial that authenticates nothing and settles six unknowns at once.**

---

## Q1. Is the bottleneck statement correct?

Six of nine clauses survive with corrections; three do not. Graded against this repo's own measurements.

| Clause | Verdict | Correction |
|---|---|---|
| "true bottleneck is per-session memory" | **Wrong as stated** | Memory is *read* by the Agent-tool spawn gate — and is its **sole** evaluated predicate there, because `hooks/agent-teams-enforce.sh:183` runs it with `CC_ADMIT_LOAD_TERM=off` — but it has never bound: 11 live evaluations, all reading 30.28–32.02 GB free-class memory against a 4 GB floor. The integers that actually refuse a session today are **router KMAX=8 per account × 4 accounts = 32** (`bin/claude-accounts:1420`) and **dispatcher ceiling 6** (`bin/cc-dispatch:314`). Neither is a memory term. |
| "~340 MB per resident session" | **Correct, mislabelled** | 340 MB is the *arrival differential* (paired, n=1,194 transitions). The session process itself is 216 MB fresh / 232 median / 283 mean / 548 max at 26 h by macOS `vmmap` phys_footprint, saturating ~450 MB within 1.5 h. Use 340 as a budget denominator, never as "per-session memory". |
| "~507 MB of MCP children that no budget counted" | **Half right** | *"No budget counted"* is true — `scripts/lib/capacity-admit.sh` has no Model Context Protocol (MCP) term at all. **507 MB is dead**: it was `ps` RSS (the instrument `session-capacity-ceiling-2026-08-09.md` §2.4 bans) over one snapshot. The term is **per-config and bimodal**, not a per-session constant: ~322 MB with the server resident, ~600 MB steady / ~1,036 MB peak once a browser is actually driven (vmmap phys_footprint, transitive ppid closure, 2026-08-10). Token-matched censuses read 62–88 MB per *live* session because they are structurally blind to the isolated Chrome + 3 Framework helpers that `chrome-devtools-mcp --isolated` spawns — no `mcp` token in their argv. **Forecast risk the statement omits: 75 of 79 `.mcp.json` files on this box declare chrome-devtools**, so today's ~12–21% hosting rate is a property of the current working-directory mix, not of the fleet. |
| "capping near ~100 resident" | **Arithmetic, never observed** | Max concurrency ever measured on this box is 31. Honest range: ~103 (real desktop state) to ~139 (against total RAM at 450 MB steady). |
| "only ~4-8 simultaneously active on 10 cores" | **Number right, cause wrong** | 2.5–4.9 runnable threads per active session is measured. The ceiling is a **policy constant** — `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0 × 10 cores` at `capacity-admit.sh:121` — not silicon. The box ran load 44.4 during the audit, degraded but alive. jcode cannot raise a policy constant; an editor can. |
| "and on 4 accounts' quotas" | **Correct** ~~and understated~~ | ~~~3.9~~ → **6.2–11.0** concurrently-active sessions sustainable 24/7. ~~Cache-read is 68% of spend at ~200K median contexts, so **halving context ≈ +50% active capacity — larger than adding a fifth account**.~~ 🚨 **STRUCK 2026-08-24 — the "understated" half is REFUTED; see §Correction below.** The clause itself stands: quota binds, it is provider-side, and it is invariant under every local runtime swap. |
| "crashes were never capacity, but compressor-segment exhaustion from unbounded toolchain bursts" | **Best-evidenced clause; slight over-reach** | 100% of `vm.compressor_segment_limit` consumed at ~28% mean segment fill, with kernel `memoryPressure` reading False. 5 of 8 ledgered events are this class (panic #2 was a spinlock timeout, incident #0 a WindowServer freeze). Ignition is always a node dev-toolchain burst — **harness-independent**. This clause is an argument *against* migrating for crash reasons. |
| "now frozen by the armed sentinel" | **Overstated** | It is armed and has now genuinely fired once (`SIGSTOP pid=23125 rss_kb=1732176 comm=node`, 2026-08-10T07:09Z). But the daemon holds fd on a 42,679-byte image while the deployed path is HEAD's 52,618 bytes — **the stale-bytes defect has recurred** — there is no `SIGCONT` sender anywhere in the tree, and it is a burst guard that produces no session ceiling. |
| the three remedies | **Mixed** | MCP consolidation: supported, but it is a one-line edit in *another repo's* `.mcp.json`. Active-count admission: **unbuilt** (the router already keys on active `k_work`; the machine-side gate does not). Cloud lane: **no longer blocked** — a full round trip executed 2026-08-11 (`cloud-reconcile: 2 ok`, VM push landed as `9096fc62`). None of the three requires a different agent CLI. |

**The framing error worth naming.** "Per-session memory" is stated as the bottleneck and "the crashes were never capacity" in the same sentence — but a burst *is* a memory term, just not a resident one, and the two bind at different design points. They cannot both be the true bottleneck. The honest single sentence: *resident memory is the term with the most headroom, active concurrency and quota are the terms that bind, and bursts are what kills the box.*

---

## Correction 2026-08-24 — this wave's quota arithmetic inherited a refuted premise

**Do not read the quota numbers in this document without this section.** Three of its findings —
the `"and on 4 accounts' quotas"` verdict above, **rank-1 lever L7**, and
[`ranked-levers.md`](jcode-due-diligence-2026-08-11/ranked-levers.md) L6 — priced quota from
`scaling-bottlenecks-2026-08-09.md`'s composition model (**cache-read 68.0% / cache-write 18.0% /
output 14.0%** at ~200K median contexts) and from its derived lever *"halving context ≈ +50% active
capacity"*. That premise has since been **refuted by direct measurement** and struck at source.

| | This wave inherited (2026-08-11) | Measured (`usage-telemetry-100p-2026-08-16/exchange-rate.md`) |
|---|---|---|
| cache-read price | 0.10× multiplier, **68% of quota cost** | Opus-5 **0.000 pp/Mtok** (p95 ≤ 0.0017 over ≥590M tokens) |
| the lever | *"halving context ≈ +50% active capacity"* | worth **0% to ≤ +16%**, never +50% — and R1 gives the **opposite** prescription: *"it authorises MORE context"* |
| sustainable concurrent-active | ~3.9 | **6.2–11.0** (model-free, `orchestration-units-2026-08-19/A6-VERIFY-quota-economics.md` §C4) |

**Ruling: class A, 2026-08-24 — the measured rate governs** (backlog `564d151b76e5`). Full reasoning,
including why the 68% premise fails under the API-list hypothesis too (**~28%**, not 68%), is in
[`scaling-bottlenecks-2026-08-09.md` **§2a**](scaling-bottlenecks-2026-08-09.md). This document was
not in that commit's file set; the correction is propagated here on 2026-08-27.

**What changes here, and what does not:**

1. **The `"4 accounts' quotas"` clause survives; only "understated" dies.** Quota still binds, it is
   still provider-side, and it is still invariant under a runtime swap — none of which rested on the
   cache-read share. What dies is the claim that the operator *understated* it by omitting a
   +50% lever that does not exist.
2. **L7 loses its quota half, and that half's sign INVERTS.** The resident-axis arithmetic
   (571 → 297 MB ⇒ 148 resident from 132) is a phys_footprint measurement and is untouched. But
   capping context does not buy active capacity — under the measured rate a cached re-read is free,
   so R1 *authorises* more context. **L7 is therefore no longer "the only lever that moves both
   axes"; it moves one.** Its ~1-day effort and 0.95 reversibility are unchanged, so it remains
   worth doing on memory grounds alone — the claim to drop is the two-axis framing, not the lever.
3. **L6's pricing is wrong in the direction that made it look cheap.** "A cold resume pays ~10× on
   ONE turn's input — repaid after ~10 subsequent turns" assumed warm re-reads cost 68% of spend. At
   0.000 they cost nothing, so there is no stream of savings to repay the resume out of: eviction's
   quota cost is the cache-**creation** on every rehydration, not a discount that amortises. L6's
   *decision-relevance* stands — the cache TTL is still the number that decides it — but it is no
   longer "eviction is quota-free".
4. **Nothing in this document's VERDICT moves.** `DO-NOT-MIGRATE` rested on the cost gate, the
   coupling census, and release maturity. The quota term was never the load-bearing part of the
   migration case, and correcting it downward-in-confidence does not create one.

---

## Q2. Does jcode address that bottleneck?

**One of four terms, and it is the term with headroom.**

- **Resident memory — yes in kind, magnitude unmeasured.** jcode's single-daemon/thin-client architecture is real code, not marketing (`crates/jcode-base/src/mcp/pool.rs`, 526 lines; `docs/SERVER_ARCHITECTURE.md:11-13`). Its marginal figure is ~10.4 MB per added session vs Claude Code's ~212.7 MB — both **Linux `/proc/smaps_rollup` PSS (Proportional Set Size), cold, ~4.5 s old sessions, zero conversation**, from a public 475-line harness (`scripts/bench_memory_cli.py`). PSS does not exist on macOS. **There is no macOS/arm64 memory number for jcode from the vendor, this fleet, or any third party.** Honest default-vs-default saving: direction plausible, **magnitude unestablished**. Discard the README's "13.9×" headline — it compares Claude Code default against jcode with embedding disabled; default-vs-default is 2.3× at one session.
- **The MCP term — no, and arguably negative.** Three compounding facts: (a) the shared pool is **daemon-only** (`manager.rs:133` — a server reaches the pool only if `self.pool` is `Some`, set only by `with_shared_pool`), so in the pane-per-process model this fleet runs the saving is exactly zero; (b) jcode's own design guidance says stateful browser servers **must** be `shared:false` (`protocol.rs:199-202`), which is precisely the only stdio server we run — so even after a daemon migration the saving on chrome-devtools is 0 MB unless we accept cross-session browser-state bleed; (c) jcode is **stdio-only** and silently skips HTTP/SSE servers (README:528), so migration would delete `uidotsh`, `motion` and `motion-plus` — the three servers that already cost zero processes — while keeping the one that costs everything.
- **Active concurrency — no.** A runnable-thread wall against a policy ceiling. Untouched.
- **Quota — no.** Same four Max plans, or a prohibited draw on them.
- **Crashes — no.** jcode still runs `next dev`, still spawns postcss pools, still hits the same segment table.

---

## Q3. Should we migrate from kitty to jcode?

**No — and the question contains a layer error worth correcting before anything else.** kitty is a terminal emulator; jcode is an agent harness that runs *inside* kitty exactly as `claude` does. jcode's own `docs/TERMINAL_CAPABILITIES.md` is a 14-row capability matrix telling TUI developers how to survive kitty's and iTerm2's quirks — a document only a guest process writes. Adopting jcode replaces **Claude Code**, not kitty. README §6's HOLD on terminal migration is not engaged.

Three independent blockers, any one sufficient:

1. **The cost gate fails, on a worse axis than a bill.** jcode's Claude path presents itself to `api.anthropic.com` as Claude Code: same OAuth `client_id` (`9d1c250a-e61b-44d9-88ed-5944d1962f5e`, byte-identical to `accounts.json`), `User-Agent: claude-cli/…`, the `claude-code-20250219` beta header, and an injected first system block *"You are Claude Code, Anthropic's official CLI for Claude."* jcode's own `OAUTH.md` states that without this *"the API will reject OAuth requests even if the token is otherwise valid"* — an explicit admission that Anthropic rejects non-official clients server-side. Anthropic's operative sentence — *"Using OAuth tokens obtained through Claude Free, Pro, or Max accounts in any other product, tool, or service — including the Agent SDK — is not permitted"* — published 2026-02-20, blocked server-side Feb–Mar 2026, fully enforced 2026-04-04. **The exposure is not a token bill; it is the four Max subscriptions the entire fleet runs on.** Compounding: jcode's *default* credential mode is `Auto`, which on OAuth failure silently falls back to a metered `ANTHROPIC_API_KEY` with only a log warning — so the day enforcement lands is the day the cost gate is breached silently, in the same code path.
   *Fair question, answered:* this repo already ships `bin/it2-kitty`, 1,003 lines built by decompiling the Claude Code binary. The discriminator is the counterparty. That shim drives a **local terminal** and presents nothing to Anthropic. The prohibited act is presenting consumer-plan OAuth credentials to Anthropic's API from a non-sanctioned client. Different act, different counterparty.
2. **The control plane does not survive.** Of 81 wired hook commands across 12 event types, jcode has 5 events and only `pre_tool` can block. 21 commands have no jcode event at all (UserPromptSubmit, Notification, PermissionRequest, PreCompact, TeammateIdle…); the 12 Stop commands map only to an observer. 45 non-doc files parse Claude Code's transcript JSONL, which jcode does not produce. Skills port nearly free (16 directories); slash commands do not (jcode has no user-defined slash surface). **Caveat, load-bearing:** this "rebuild" number rests on `crates/jcode-harness-api`, which **nobody in the wave opened**. That crate emits `ServerEvent::TurnDone` and accepts `ApiRequest::SendMessage` over a socket — if it does what its schema says, this is a *port* (Stop-shaped hooks become TurnDone-driven socket clients), not a rebuild. Fifteen minutes of reading settles it and it is the highest-leverage desk read available.
3. **Production-dependency hygiene.** v0.75.0 was published 44 minutes after CI failed on that exact commit; master's last green run was 9 days earlier. 6,937 of 6,849 commits across five git identities are one person; PRs are `collaborators_only`; there is no `SECURITY.md`. Issue #883 (untriaged) reports `~/.claude` hardcoded in ~11 paths with `CLAUDE_CONFIG_DIR` ignored — this fleet's config lives at `~/.claude-next`. Issue #853 (open, high, macOS/arm64) reports jcode itself growing to 26.2 GB RSS in 15 minutes and contributing to a kernel watchdog panic — the exact failure mode this box has suffered.
   *Discount honestly:* the installer risks the wave loaded (split trust root at jcode.sh, `xattr -d com.apple.quarantine`, seven rc files rewritten, `server reload` on upgrade) are **avoidable** — v0.75.0 ships plain `jcode-macos-aarch64.tar.gz` + `SHA256SUMS` as GitHub assets. Never run `curl | bash`. Telemetry is on by default but disabled by `DO_NOT_TRACK=1`; content sharing is already opt-in in code.

---

## Q4. Expected outcomes

Same units throughout: 340 MB arrival cost / ~450 MB steady, macOS `vmmap` phys_footprint. Usable ~44 GB after a ~20 GB non-Claude baseline.

| Branch | Effort | Resident ceiling | Active ceiling | Deaths | Risk |
|---|---|---|---|---|---|
| **Do nothing** | 0 | ~132 (340 MB) / ~139 (450 MB steady) | 4–8 | ~5 per 11 days | sentinel running non-HEAD bytes |
| **L7 + L1 + L2** (context cap, MCP opt-in, burst bound) | **~4 agent-days** | ~148–155 | 4–8, but **+~50% quota-effective** from halved context | bounded | none — all local config |
| **jcode migration** | 60–120 agent-days | 727–1,800 *if* the Linux marginal transfers to macOS (unmeasured) | **unchanged** | **unchanged** | four Max accounts wagered; ~58% of hook layer rebuilt (disputed, see Q3.2); single daemon = single fault domain for all sessions |
| **jcode local-model lane** (additive) | **~1 agent-day** | n/a | **+N sessions off Max quota** | n/a | ~0 — scratch prefix, nothing authenticated |

The line that decides it: **L7 + L1 + L2 reaches the stated 150-resident target for about four agent-days, without a harness change.** jcode reaches it with room to spare, on the axis that already has room, for 15–30× the effort and the four subscriptions.

---

## Q5. Is another shim layer worth it for /handoff and Agent-Team subagents?

**The stack you are worried about does not exist — but the real integration cost is the inverse of the one you named.**

- There is no `it2 → kitty → jcode` chain. jcode sits *beside* `claude`, not under kitty.
- The actual conflict: `crates/jcode-terminal-launch` is a **1,692-line pane spawner** with its own per-backend split/open verbs (tmux `split-window -h`, zellij `new-pane --direction right`, kitty `kitty --title T -e prog`, iTerm2 via osascript). Adopting jcode installs a **second, non-interoperable pane authority** over the same kitty tree that `handoff-fire.sh` / `bin/it2-kitty` / `bin/cc-pane` already own. Its native kitty path opens a **new OS window per spawn** — the layout README.md:649 measured as the expensive one ("windows for 30 panes: 1" is why kitty won). Reconciliation runs through `[terminal].spawn_hook`, one more owned config surface.
- Counterweight, stated honestly: `spawn_hook` is a **better seam than anything Claude Code offers** — a documented, env-passing takeover point (`JCODE_SPAWN_KIND/SESSION_ID/TITLE/CWD/COMMAND`) for what `it2-kitty` achieves by decompilation. That is an argument for what Claude Code *should* ship, not for migrating.
- **Terminal cost is not the deciding term anyway.** `bin/cc-pane:27-30` already resolves any driver X to a sibling `cc-pane-X`; D4 sizes one at ~150 lines. The 1,003-line it2-kitty price was paid once, to defeat a hardcoded vendor gate. Adding a terminal today is cheap; replacing the harness is not.
- **The Agent-Team half is the unpriced option, and it is the most interesting thing in this wave.** jcode's **headless swarm worker** is a much closer analogue to an Agent-Team assignee than to a `/handoff` pane — and an assignee needs almost none of what breaks: no Stop hook, no close protocol, no `/wrap` ledger, no pane identity, no transcript parser. The entire migration cost priced above is a cost of the **interactive desk lane**. Nobody scored jcode as an assignee runtime. That is where the option value sits, and it is measurable in the trial below.

---

## Q6. Should jcode go through README section 6 rigor?

**No — §6's instrument is a terminal bake-off and returns a non-verdict on a harness by construction.** Pointed at jcode, `scripts/terminal-bench.sh` fails on four of five axes: the window census shells `window-census.swift` against `CGWindowList` and a TUI owns zero CGWindows (`LAYOUT_STATE=uncertified`); the GPU discriminator falls to the default arm and returns `NO-DATA`; `--panes N` normalises by terminal panes, a unit jcode lacks; and the mach-port/window-drift leak axis is a WindowServer phenomenon of a windowed app. Every run emits `verdict=PARTIAL`, exit 0 — the token this repo's own header defines as not-a-verdict. Only the `top -l 2` reading primitive is reusable, and it should be lifted into a new harness-bench rather than the terminal script pointed sideways.

**The §6-shaped question jcode *does* touch is the console, and jcode is not the best candidate there.** §6 says the beacon is built and has no face. Corrections to what the wave first reported: jcode's `/active` session manager **shipped** in v0.39.0, `SessionSource::ClaudeCode` is first-class, and `crates/jcode-base/src/claude_live.rs` enumerates live Claude Code sessions from `~/.claude/sessions/<pid>.json` — but `process_identity_matches` is `#[cfg(not(target_os = "linux"))] -> false` (`claude_live.rs:182-185`), so **the cross-harness console is Linux-only today**. `jcode-desktop2` (winit + wgpu + Vello, no PTY, "Status: Proposed", in **no** v0.75.0 release asset) is precisely the artifact §6 names as missing — a convergence signal for the roadmap, not an adoptable component. Meanwhile **herdr** (27,171 stars, Apache-2.0) ships a face that classifies Claude Code panes today with zero hooks, and **cmux** is already proven for external drive from an iTerm2-parented shell. If the console is what you actually want, those are the leads.

---

## Ranked levers — what to do instead

Scored `(sessions or protection gained × reversibility) / agent-days`.

| # | Lever | Arithmetic | Effort | Rev. |
|---|---|---|---|---|
| **1** | **L7 context-ceiling cap** (`CLAUDE_CODE_DISABLE_1M_CONTEXT` / cap 200K) | Cost model, phys_footprint, n=21, R²=0.71: `MB = 228 + 0.343 × K-input-tokens + 0.071 × min`. Every live session runs a 1M window with autocompact off ⇒ a 343 MB per-session ceiling. Capping at 200K: 571 → 297 MB ⇒ **148 resident, from 132** — this half stands, and it is measured on memory, not on quota. ~~And on the quota side, cache-read is 68% of spend ⇒ **+~50% active capacity**. The only lever that moves both axes.~~ 🚨 **STRUCK 2026-08-24 — the quota half is REFUTED and its sign INVERTS; see §Correction. L7 is a RESIDENT-axis lever only.** | ~1 day | 0.95 |
| **2** | **L2 burst bound + fix the admission term** | 5 kernel deaths in 11 days; gains 0 resident, protects all 150. `cc_hw_headroom_gb()` counts anonymous-inactive as reclaimable, over-reporting by ≥10 GB with the error *growing* under fan-out; add a process-class cardinality term that would have caught the 736-process node swarm ~60 s early. Both are small edits to one live-symlinked library. | ~2 days | 0.9 |
| **3** | **L1 MCP opt-in** (edit reso's `.mcp.json`, not ours) | **Removes** the term rather than pooling it: 1,050 MB freed today; at 150 sessions holding ~21% hosting, ~11.2 GB ≈ **33 sessions**, and it keeps the three HTTP servers. Strictly dominates jcode's best case (which leaves one 350 MB stack and drops the HTTP servers). | ~1 hour | 1.0 |
| **4** | **L6 idle eviction** — *blocked on one 0.5-day measurement* | `claude --resume` appends to the same transcript with a fresh process, so a closed session is disk-durable and rehydratable at the 228 MB floor. If the Anthropic prompt cache really goes cold at ~5 min idle, eviction is quota-free and **150-resident is an incoherent target**. Measure the cache TTL first; nothing else here is worth building until it is settled. | 0.5 day to decide | 1.0 |
| **5** | **L3 cloud lane** | Now executes (round trip verified 2026-08-11). Zero local RAM, zero local CPU — the only lever besides L7 that raises the *active* ceiling. Blocked on a shallow-clone blast radius and an unmeasured per-session token draw. | ~4 days | 0.8 |
| **6** | **jcode as an additive local/Codex lane** (see below) | Off-Max-quota active capacity for headless bulk work. | ~1 day | ~1.0 |
| **7** | jcode migration | Wrong axis, wrong price, four accounts wagered. | 60–120 days | 0.15 |
| — | L8 hardware | 150 × 450 MB = 67.5 GB: trivial on 256 GB, impossible on 64. Excluded by **frozen scope, not by evidence** — say so rather than scoring it away. | — | — |

---

## The one jcode thing worth doing

**Run jcode as an additive lane, not a replacement.** This was never scored because the wave scored *migration*.

The assembled case, from the wave's own findings: jcode-on-Codex passes the cost gate (`~/.codex/auth.json` read in place, ChatGPT Plus already held, `bills_outside_plan=false`); `ollama` / `lmstudio` pass by construction (no meter exists); jcode passes the provider registry's routability test (`jcode run '<prompt>'` non-interactive — the criterion antigravity failed); and headless bulk work (log triage, bulk grep-summarise, doc sweeps) needs **none** of the control plane that breaks. The standard dismissal — *"second harness, not added capacity; it rides the same ChatGPT Plus"* — was written against the **resident** axis. Against the **active** axis, which is the one that binds, a lane costing zero Max quota is added capacity by definition.

### The trial: 90 minutes, nothing authenticated

Download `jcode-macos-aarch64.tar.gz` from the GitHub release (**never `curl | bash`**), verify against `SHA256SUMS`, extract to a scratch prefix with `HOME` and `JCODE_HOME` redirected. Authenticate nothing. Run `jcode serve` + 4 clients against a local `ollama` model on a scripted 40-turn agentic loop (12 file reads, a test suite, 8 edits, 20 greps), sampling `top -l 2 -o mem -stats pid,command,mem` every 60 s for 90 minutes, summing each process **tree** by walking `ps -Ao pid,ppid,comm` from each root.

Instrument note: `top -l 2` is phys_footprint-equivalent and **4.8× cheaper than vmmap** (verified live: pid 6687 read 302.4M via `vmmap --summary` in 7.077 s vs 302M via `top` in 1.485 s; box-wide sweep 1.63 s). `ps` RSS is banned. Saturation is done at ~1.5 h — this repo already refuted a lifetime leak, so an overnight run buys nothing.

It retires six load-bearing unknowns at once, each of which currently anchors a different verdict:

1. jcode's macOS/arm64 footprint under real context load, on our sanctioned instrument.
2. The server-vs-client byte split — the unit the ~10.4 MB marginal is quoted in.
3. Session identity: does a jcode session have a pid the pane layer can address?
4. The harness API: attach a client, observe `TurnDone`, inject a message — settles rebuild-vs-port empirically.
5. Four-account coexistence: start two daemons under two config dirs and see whether they collide. **Concrete, already-found blocker:** `crates/jcode-harness-api/src/sockets.rs:16-45` resolves `JCODE_RUNTIME_DIR` → `XDG_RUNTIME_DIR` → macOS `TMPDIR` → `temp_dir()/jcode-<uid|user>`. Our four Max accounts are **one unix user with four `CLAUDE_CONFIG_DIR`s**, so four daemons collide on one socket path unless `JCODE_RUNTIME_DIR` is set per account. Env-var override exists — which also suggests issue #883's "`CLAUDE_CONFIG_DIR` ignored" deserves a check rather than adoption as fact.
6. The console's macOS gate: run `/active` and see whether it is empty.

**Controls that can fail** (otherwise the run is void): a Claude Code arm run identically must reproduce the fleet's own model (~228 MB floor + ~0.343 MB per 1K tokens); `vmmap` and `top` must agree within 5% on the same pid in the same minute; a deliberate `ps -o rss` re-read must inflate ≥1.6×, proving the census really reads footprint; and jcode must be measured embedding-ON *and* -OFF, since the vendor's own 6.0× spread at one session makes a single jcode number meaningless without naming the config.

### Kill conditions, in firing order

- **K0 — cost.** Any configuration drawing on the four Max plans: **stop, do not install that path.** File the provider registry row `in_scope:false`. The trial above sidesteps K0 entirely by authenticating nothing.
- **K1 — capability.** If `crates/jcode-harness-api` cannot observe turn completion and inject a message, CLOSE_INTEGRITY has no expression and the interactive lane is dead. *Read the crate before spending an hour on anything else.*
- **K2 — identity.** If a jcode session has no stable, addressable per-session pid or socket id, every addressing, wake, mail, custody and teardown mechanism here loses its key. Stop.
- **K3 — memory.** At 4–8 sessions with 400K-token contexts, if jcode's server+clients tree is not ≤50% of the Claude Code arm, stop: below 2× the win does not pay for K1/K2.
- **K4 — blast radius.** `kill -9` the daemon with sessions attached. If any conversation is unrecoverable, stop — one process holding 150 sessions is a worse failure mode than 150 holding one each, on a box whose defining failure is dying whole.

---

## What is unknown, and what resolves it

| Unknown | Resolves by |
|---|---|
| jcode's macOS/arm64 footprint under real context load — **unmeasured by the vendor, this fleet, and every third party**. The entire memory case is this number. | The 90-minute trial above. |
| Whether `crates/jcode-harness-api` can inject at turn end — decides *port* vs *rebuild*, and two axes' verdicts turn on it. | 15-minute read of `client.rs` / `events.rs` / `requests.rs` / `harness_api_tests/capability_coverage.rs`. |
| Anthropic's policy at **primary source** — both official URLs returned 404; the ban rests on six agreeing secondaries plus one verbatim server error string. | Fetch the live Usage Policy / Consumer ToS and the Legal & Compliance authentication section. **Note: this does not move the recommendation** — the FAIL survives a permissive reading via the Auto-mode metered fallback and impersonation-by-design. Do it, but not first. |
| The Anthropic prompt-cache TTL as this fleet experiences it. | ~0.5 agent-days. It decides whether idle eviction is free and whether 150-resident is even a coherent target. Nothing else in the lever table is worth building until this is settled. |
| The `claude.exe` self-burst trigger — 54 processes exceeded 4 GB in 11 days, max 41 GB, ramping ~8 GB/min, cause unidentified. At 150 resident that is ~3 events/hour, each able to erase the whole burst margin. | Unbuilt instrument (a page-only `claude.exe` watch). **This term could invalidate any 150-resident plan regardless of harness — including jcode's, since the burst is inside the agent process.** |
| Whether the compressor sentinel's running 42,679 bytes differ *functionally* from HEAD's 52,618. | Read the running image. It is a live-layer convergence defect in our own operations and should be fixed before any migration is discussed. |
| Per-session CPU under jcode vs Claude Code at matched workload — the 4–8-active wall is a runnable-thread wall, and nobody has measured jcode's thread footprint. A Rust harness plausibly beats a bun-compiled JS one, and if it does by a large factor jcode rises on the axis that actually binds. | Zero evidence either direction today; the trial's `top` sweep captures threads for free. |
| Whether one `jcode serve` daemon can serve sessions across many project directories correctly, or would spawn reso's chrome-devtools for **every** session (strictly worse than today). | `client.rs` + the serve entrypoint, plus a 2-session trial in two different repos. |

**One instrument warning that should outlive this memo:** `WebFetch` on `https://jcode.sh/docs` returned *"jcode is described as 'Anthropic's official CLI for Claude'"* — a string that appears **zero times** in the 23,054-byte page and is verbatim from the calling agent's own system prompt. The summarizer substituted the agent's context for the page. Any claim about jcode's identity sourced via WebFetch in this wave should be re-verified by direct fetch plus grep.

---

## Appendix — completeness critic

## 1. Modalities never run

**Nobody ever ran jcode.** Ten axes, zero execution. Every figure about jcode is a read of source, docs, GitHub API, or the vendor's own table. `trial-design` designed a 3-hour minimum-viable trial and no one ran step 1 of it — and steps K0–K2 of that design are explicitly *free of the cost gate* (a sandboxed `HOME`, no OAuth minted, no plan quota touched). The wave concluded "do not adopt" from a corpus that contains no observation of the artifact.

**Source-reading was applied asymmetrically, and it left resolvable unknowns standing.** I closed one in 90 seconds. Two independent axes (`layer-identity`, `shim-frame`) list "jcode's macOS socket path" as UNKNOWN. It is in `crates/jcode-harness-api/src/sockets.rs:16-31` (fetched live): `JCODE_RUNTIME_DIR` → `XDG_RUNTIME_DIR` → `#[cfg(target_os="macos")] TMPDIR` → `std::env::temp_dir()/jcode-<uid|user>`. The pattern is that axes read source when the read would establish a *cost* and declared UNKNOWN when it would relieve one.

That same 30-line read produced a finding **no axis reached**: the fallback discriminator is `$UID` or `$USER` (`sockets.rs:37-45`). This fleet's four Max accounts are one unix user with four `CLAUDE_CONFIG_DIR`s — so four jcode daemons collide on one socket path unless `JCODE_RUNTIME_DIR` is set per account. That is a concrete, checkable four-account blocker, and the wave instead argued the four-account question from an *untriaged single-reporter issue* (#883).

**Never read at all, all cheap:**
- `crates/jcode-harness-api/` implementation — the crate the `coupling-census` skeptic used to refute that axis's own top claim. It exists and is tested: `client.rs`, `events.rs`, `requests.rs`, `sockets.rs`, plus `harness_api_tests/{capability_coverage.rs, schema_snapshot.rs}` (verified live). The wave's largest single cost number ("58% of hooks dead") rests on the crate nobody opened.
- `scripts/bench_memory_cli.py` was read by exactly one axis (`memory-claim`), while two others asserted it does not exist (see §3b). It is 15,966 B at `0f6a55e4` (verified live).
- `crates/jcode-swarm-core`, `SWARM_ARCHITECTURE.md`, `SWARM_TASK_GRAPH.md` — unread, so the operator's Agent-Team half of the shim question is unanswered (below).
- jcode's `jcode.sh/sdk` — explicitly declared unread by `coupling-census`.
- **No upstream contact.** Filing "does `CLAUDE_CONFIG_DIR` work / can four accounts coexist" on a repo with automated triage costs nothing and was never done.
- **No `strings` on a downloaded binary** (`risk-maturity` says so itself) — so the network-endpoint audit is partial and the telemetry finding is one-crate.

**Operator questions no axis actually answered:**
- **"Expected outcomes?"** Nobody wrote an outcomes model — do-nothing baseline vs adopt, with dates and a stated confidence. `ranked-levers` ranked *levers by score*, which is a different artifact; it never says what the box looks like in 30 days under either branch.
- **"Worth another shim layer for /handoff **and Agent-Team subagents**?"** The /handoff half was answered five times. The Agent-Team half was answered only as loss (`coupling-census`: no per-agent model pinning, no `TeammateIdle`, no `shutdown_request`). No axis asked the forward question, even though `layer-identity` raised it and dropped it in the same finding: jcode's **headless swarm worker is the closer analogue to an Agent-Team assignee than to a /handoff pane**, and assignees need almost none of the close protocol. Nobody priced jcode as an assignee runtime.
- **The installer condemnation binds nothing, and no axis noticed.** `risk-maturity` builds four risks on `jcode.sh/install` (split trust root, `xattr -d com.apple.quarantine`, seven rc files, `server reload`). v0.75.0 ships `jcode-macos-aarch64.tar.gz` + `SHA256SUMS` as plain GitHub release assets (verified live). Every one of those four risks is avoided by `curl` + `tar` and never running the installer. The wave carried an avoidable risk into the verdict as if it were structural.

## 2. Conclusions resting on unverified claims — ranked by decision-flip weight

**(1) The cost gate — the only one that flips "never install" to "trial it."** `cost-gate`'s FAIL rests on six secondary sources; both Anthropic primary URLs returned 404, and its own skeptic corrected the enforcement date (Jan 9 → Apr 4), corrected the citation (not in the Consumer ToS body), and refuted "only plan-drawing path." The claim now standing is *asset-forfeiture risk under a policy nobody in this wave read at primary source*. If the policy's scope is redistributed products rather than personal use of an OSS client on one's own subscription, the verdict flips. **Unremarked consistency problem:** this repo already ships `bin/it2-kitty`, 1,003 lines built by decompiling the Claude Code binary to defeat a vendor gate (`shim-frame` finding 2). No axis asked why impersonating Claude Code's pane backend is sanctioned here while impersonating its wire identity is disqualifying. That asymmetry may be entirely defensible — nobody defended it.

**(2) "jcode's turn_end cannot reach the model" ⇒ "58% of hook commands dead / CLOSE_INTEGRITY must be rebuilt."** This is the wave's biggest cost number and it was refuted *by its own skeptic* using `jcode-harness-api` (`ServerEvent::TurnDone` + `ApiRequest::SendMessage`, plus `pre_tool` exit 2 returning stderr to the model). Neither the claim nor the refutation opened the implementation. If the harness API does what its schema says, migration is a **port** (Stop-shaped hooks become TurnDone-driven socket clients) not a rebuild, and `trial-design`'s K1 — expected to be the free kill — does not fire. Two axes' verdicts (`coupling-census`, `trial-design`) turn on this single unopened crate.

**(3) The memory saving.** `memory-claim`'s "200–260 MB/session, central ~230" is INFERRED from a Linux-PSS cold marginal times two invented transfer bands, one of which borrows *Claude Code's* growth envelope for jcode. Its own skeptic reduced this to "direction plausible, magnitude unestablished." Every downstream ranking treats it as an input.

**(4) `CLAUDE_CONFIG_DIR` ignored (issue #883).** Untriaged, single-reporter, unverified here. `risk-maturity` calls it a day-one blocker; if false, the strongest fleet-specific objection evaporates. Ten minutes of source-reading against the eleven cited call sites would settle it — and `sockets.rs` shows jcode *does* honour env-var overrides where it matters, so the claim deserved a check.

**(5) "jcode's Claude usage lands on the 5h/7d plan windows."** INFERRED from jcode reading the subscription usage endpoint. Correctly *not* measured (measuring it is the prohibited act). Flag it: the cost-gate verdict's mechanism half is inference, honestly labelled, and it is load-bearing.

## 3. Where axes contradict

**(a) The MCP term — a >10× spread on the same box within 24 hours, unadjudicated.**

| Source | Per live session | Per hosting session | Instrument |
|---|---|---|---|
| `bottleneck-audit` C3 (the operator's own figure) | 507 MB | — | ps RSS (banned) |
| `memory-claim` (census-fleet) | 62 MB | ~325 MB | argv-anchored, ppid-rooted |
| `mcp-term` main | 75–88 MB | ~350 MB | vmmap + `top -l1` |
| `ranked-levers` | 190 MB | — | phys_footprint |
| `mcp-term` **skeptic** | — | 322 idle / **600 steady / 1,036 peak** | vmmap phys_footprint, transitive ppid closure |

`mcp-term`'s verdict ("19–21%, third term, the counterfactual dominates") and its own skeptic ("53–79% of a carrying session's cost, the operator's ~60% is reproduced") are opposite conclusions inside one axis, and no other axis reconciles them.

**The skeptic is better evidenced**, on a mechanism the others cannot answer: `chrome-devtools-mcp --isolated` spawns a full isolated Chrome plus three Framework helpers whose argv contains no `mcp` token, so every token-matched census is *structurally blind* to 577 MB of the subtree it is measuring. This repo's own memory index carries that failure twice (`pgrep -f matches briefs`, `caller census: name ≠ path`). Part of the spread is denominator (per-live vs per-hosting) and part is lazy materialisation (server-resident 322 MB vs browser-driven 600 MB) — but no axis stated the term in a form both readings can be checked against, and only the skeptic surfaced the forecast-relevant fact: **75 of 79 `.mcp.json` on this box declare chrome-devtools**, so today's 12–21% hosting rate is a property of the current cwd mix, not of the fleet.

**(b) "The benchmark has no methodology" — a lookup miss reported as absence.** `risk-maturity` ("published with no methodology") and `trial-design` ("NO stated methodology anywhere… the only instrument word is 'PSS'… a trial cannot replicate jcode's numbers") both searched the README and `jcode.sh/bench` and concluded absence. `memory-claim` read `scripts/bench_memory_cli.py` line by line — probe string at :20, settle at :22, `smaps_rollup` at :309-317, process-tree union at :287-330, temp `JCODE_HOME` at :356-397 — and `risk-maturity`'s own skeptic names it a 475-line public harness with a standing CI regression gate. I confirmed the file exists (15,966 B, `0f6a55e4`). **`memory-claim` is right and the other two are wrong**, by the exact defect this repo's memory index names (`lookup miss ≠ absence`). It matters: `trial-design`'s stated reason for designing from scratch is false (its *conclusion* survives for a different reason — the harness reads `/proc` and cannot run here), and its top claim was additionally refuted for importing the latency tables' footnote onto the memory tables.

**(c) Does memory bind?** `ranked-levers` top claim: memory is not binding, ~139 headroom, therefore jcode ranks 7/8. Its skeptic: binds at 60–75, therefore MCP consolidation *rises*. `bottleneck-audit`: no live gate reads any term the operator names. Its skeptic: `agent-teams-enforce.sh:183` runs `CC_ADMIT_LOAD_TERM=off`, making memory headroom the *sole* evaluated predicate on the highest-volume spawn surface. **The skeptics are better evidenced on the decisive sub-point**, and it is a code fact, not a number: the memory term is evaluated *second* and short-circuited by the load term (`capacity-admit.sh:320-368`; `handoff-fire.sh:3815-3862` comment "Runs ONLY once the load term admitted"). So "0 of 127 refusals were memory" is what the mechanism must emit regardless of whether memory binds — a non-verdict, quoted by `ranked-levers` as an acquittal, and its entire ordering rests on it. **jcode's rank is not established.**

**(d) Has jcode shipped a console?** `shim-frame` top claim: Proposed, unbuilt, structurally incapable of rendering a Claude Code session. Its skeptic: `/active` shipped in v0.39.0; `SessionSource::ClaudeCode` is first-class; `claude_live.rs` enumerates live Claude Code sessions from `~/.claude/sessions/<pid>.json` with a `PickerResult::TakeOverClaude` verb. `layer-identity` sides with the doc's `Status:` header. **The skeptic wins** — a design doc's Status measures the doc, and the tree is where ship-state lives. The residual is a **one-line platform gate**: `process_identity_matches` is `#[cfg(not(target_os="linux"))] -> false` (`claude_live.rs:182-185`), so the cross-harness console is Linux-only *today*. The wave recorded this as a dismissal; it is a dependency on an upstream `#[cfg]`.

**(e) `jcode-terminal-launch`: gift or conflict?** `layer-identity` and `coupling-census` call `spawn_hook` "the one place migration would REDUCE code." The `layer-identity` and `shim-frame` skeptics call the same crate a second, non-interoperable pane authority over the same kitty tree. Both are true under different adoption modes (gift if wholesale, conflict if beside) and no axis says so.

## 4. The steelman the wave under-weighted

The wave was anchored twice: by the operator's "migrate from kitty to jcode" (correctly called a category error — then ten axes spent their budget on *migration cost*), and by his bottleneck statement's first clause (per-session **resident** memory). Both anchors point away from the strongest case.

**jcode is not a replacement candidate. It is a second lane on a quota pool the Claude fleet cannot reach — and quota is the wall the operator himself named second and `bottleneck-audit` C6 grades as the hardest.**

Assemble the wave's own findings, which no axis assembled:
- `cost-gate`: jcode-on-Codex **passes** the gate — ChatGPT Plus, already held, `bills_outside_plan=false`, OAuth via `~/.codex/auth.json` read in place. Local `ollama`/`lmstudio` pass by construction (no meter exists).
- `trial-design`: jcode passes the registry's *routability* test — `jcode run '<prompt>'` non-interactive, the criterion antigravity failed.
- `bottleneck-audit` C6 + `ranked-levers`: 4 Max accounts sustain **~3.9 concurrently-active sessions 24/7**. That is provider-side and invariant under every local lever in the ranking. `L3` (cloud) ranks 5th purely because it is the only lever that moves it.
- `coupling-census` / `trial-design`: headless bulk work (log triage, bulk grep-summarise, doc sweeps) needs **no** Stop hook, no close protocol, no pane identity, no transcript parser. The entire migration cost the wave priced is a cost of the *interactive desk lane*, and it does not apply here.

The dismissal was one sentence, borrowed from the `pi-codex` row — *"SECOND HARNESS, NOT ADDED CAPACITY… rides the SAME ChatGPT Plus"* — and it was written against the **resident** axis. Against the **active** axis it is wrong in the direction that matters: a lane on ChatGPT Plus or a local model adds active-session capacity that costs zero Max quota, zero close-protocol loss, and zero shim. On `ranked-levers`' own scoring axis (gain × reversibility / effort), a scratch-HOME jcode-on-ollama lane at ~1 agent-day and reversibility ≈ 1.0 does not score 7th of 8. It was never scored at all, because the wave scored *migration*.

**Three secondary under-weightings:**
1. **jcode is a working, MIT-licensed reference implementation of the architecture this repo's own research says it wants.** `ranked-levers` concludes the right target is "~150 **addressable** sessions with residency following demand." That is `jcode serve` + thin clients. `layer-identity` found `jcode-desktop2` is "precisely the artifact README §6 names as missing." The wave treated "it's roadmap" as a dismissal instead of "someone already built the hard part and published it" — the value of reading it does not require adopting it.
2. **Most of the risk pile is defusable, and the wave priced it as structural.** Installer → use the tarball (verified: assets are plain tarballs). Telemetry → `DO_NOT_TRACK=1`, and content sharing is already opt-in *in code*. Auto-mode metered fallback → pin `JCODE_*_AUTH`. Socket collision → `JCODE_RUNTIME_DIR` per account.
3. **The four-account question was never actually tested**, and `sockets.rs` shows the mechanism (env-var override) that would make it work.

**What the steelman does not rescue:** the Claude-provider path still fails the cost gate on impersonation-plus-forfeiture, and nothing here argues for migrating the interactive desk lane. The steelman is *additive lane*, not *migration*.

## 5. The single cheapest measurement

**Download `jcode-macos-aarch64.tar.gz` from the GitHub release (never `curl | bash`), extract to a scratch prefix with `HOME` and `JCODE_HOME` redirected, authenticate nothing, and run `jcode serve` + 4 clients against a local `ollama` model on a scripted 40-turn loop, sampling `top -l 2 -o mem -stats pid,command,mem` every 60 s for 90 minutes.**

~30 minutes of setup, ~90 minutes unattended, one scratch dir, **zero OAuth grants minted, zero plan quota drawn, zero accounts wagered** — so it does not touch the cost gate, which forbids drawing on the plans, not executing a binary. It is `trial-design`'s own K1–K3 with the Anthropic provider removed, which is what makes it free.

It is the cheapest because it is the only act that retires **six** currently-unknown, load-bearing quantities at once — each of which today anchors a different axis's verdict:

1. **jcode's macOS/arm64 footprint under real context load, on this repo's sanctioned instrument** — unmeasured by the vendor, this fleet, and every third party. The whole memory case is this number.
2. **The server-vs-client byte split** — documented in prose on no platform, and it is the unit the ~10.4 MB marginal is quoted in.
3. **K2 / session identity** — does a jcode session have a pid the pane layer can address? Inferred from a doc; never observed. `trial-design` calls this a STOP condition.
4. **K1 / the harness API** — attach a client, observe `TurnDone`, inject a message. Settles the wave's biggest cost number (§2.2) empirically instead of by crate-reading.
5. **`CLAUDE_CONFIG_DIR` / four-account coexistence** — start two daemons under two config dirs and see whether they collide on `$TMPDIR` (§1).
6. **The console's macOS gate** — run `/active` and see whether it is empty, confirming or refuting `claude_live.rs:182-185` in one command.

**Cheapest desk-only alternative if no execution is permitted:** read `crates/jcode-harness-api/{client,events,requests}.rs` plus `harness_api_tests/capability_coverage.rs` (~15 minutes, verified present). It settles only item 4 — but item 4 alone decides whether `coupling-census` and `trial-design` are reporting a rebuild or a port, and both currently return "kill" on a crate neither opened.

**The measurement NOT to take first:** the Anthropic primary-source policy read. It is cheap, it should happen, and it does not move the recommendation on its own — `cost-gate`'s FAIL survives a permissive reading via the Auto-mode metered fallback and the impersonation-by-design. It gates the *Claude-provider* lane only, which the steelman in §4 does not need.
