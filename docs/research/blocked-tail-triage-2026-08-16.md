# Blocked-tail triage — 2026-08-16

**Scope.** The 179 `status=blocked` backlog rows remaining after excluding the ~51 `re-land <branch>`
rows (lead-owned) and the ~50 "worktree occupancy oracle could not be RESOLVED" rows (another
agent's). Read-only pass: no row was edited, unblocked, closed or dispatched.

**Real count: 179** (store-wide: 1644 done / 280 blocked / 267 open / 4 claimed; 280 − 51 re-land −
50 occupancy = 179).

## Age distribution (firstTs)

| Month | Rows |
|---|---|
| 2026-07 | 21 |
| 2026-08 | 158 |

Daily: 07-20 4 · 07-25 2 · 07-26 5 · 07-29 1 · 07-30 3 · 07-31 6 · 08-01 1 · 08-02 9 · 08-03 9 ·
08-04 5 · 08-05 5 · 08-06 1 · 08-07 16 · 08-08 9 · 08-09 13 · 08-10 21 · 08-11 32 · 08-12 5 ·
08-13 3 · 08-14 4 · 08-15 3 · 08-16 22.

**The pile is young and bursty.** 08-10/08-11 alone contribute 53 rows (30%), and that burst is
almost entirely the deploy/live-layer class below — i.e. one mechanism generated a third of the
month.

## Clusters (n ≥ 2, after normalising digits/hashes)

| Cluster | n | Disposition |
|---|---|---|
| deploy-live refuses / live layer N behind at a named live HEAD | 23 | **21 STALE**, 1 UNDECIDED, 1 agent-doable |
| C10 activation / migration (launchd · settings.json · ~/.zshrc) | 22 | TRULY-OPERATOR (5 are duplicates) |
| pane / pid / worktree teardown by hand | 10 | **10 STALE** |
| value fork ("decide", "rule on", "pick", "ratify") | 30 | TRULY-OPERATOR |
| credential / token mint / browser OAuth | 19 | TRULY-OPERATOR |
| human contact / phone / physical device | 15 | TRULY-OPERATOR |
| `dead-worker stall after N dispatch attempt(s)` | 6 | **6 AGENT-DOABLE** |
| doc_classifier "operator merges — no /ship rail" | 5 | 1 survivor + 3 duplicates + 1 sibling |
| land-blocked by box contention (branch complete, gate cut) | 5 | **5 AGENT-DOABLE** |
| `pre-existing worktree wt-<id> is behind origin/main` | 2 | DUPLICATE of 925d843f6665 |

## The measurement that moved the pile

Current live layer HEAD = **8969739161f1** (`~/.claude/autonomy/postland/deploy-last-advance`,
advanced 2026-08-16 13:25). Every live HEAD named by a deploy-lag row —
`203eb4410301 · 6d782c198d9a · 32355a9b1fbe · 800ea2437257 · e0c6b4e877d7 · 56744cfd5b69 ·
088875158755 · 699bbb743aa2 · ed095d4be3ea · 145fab7d2675 · 86e354262d34 · 6c5d778b9312 ·
3aa96304253c · a54569dbf020 · 237ecf2438f9 · dec39a391362` — tests **ANCESTOR** of it under
`git merge-base --is-ancestor`. The shared checkout is now **0 ahead / 0 dirty tracked files**
(three rows demand a `reset --hard` that is a no-op today). And every named ADDed file those rows
said was absent is a live symlink now, checked per path: `scripts/cloud-return.sh`,
`scripts/gate-red-census.sh`, `scripts/cloud-refusal-route.sh`, `scripts/lib/spawn-presence.sh`,
`hooks/accounts-board.sh`, `bin/cc-offload`, `bin/it2-kitty`, `bin/cc-dispatch`, `providers.json`,
`commands/resume-sessions.md`, `scripts/limit-recover/lr-fire-resume.sh`.

## Per-row table

| id | needs (normalised, ≤100 chars) | disposition | evidence | effort |
|---|---|---|---|---|
| `01288c0aadf2` | the postland verifier's launchd job still carries ProcessType Background, which pins its corpus at P | DUPLICATE | survivor 362fd0c7572f — same activation 37-postland-band-activate.sh | — |
| `01487ffd8417` | Run E1 concurrent-login probe on next3 (0 live sessions) — decides Variant A (per-slot de-sharing, f | TRULY-OPERATOR | spends a real login on next3 to decide a variant fork | — |
| `01ab05685857` | postland-verify is INERT — newest GREEN stamp 46h old (max 24h), so nothing is re-proving trunk; thi | AGENT-DOABLE | premise false — postland-verify is ALIVE and stamping; today's real blocker is a RED prelint (see FLAG A) which is agent-fixable | M |
| `02ba4e52389a` | LAND-BLOCKED by machine-wide test contention, NOT by a defect. Branch wt-H is complete, clean, rebas | AGENT-DOABLE | branch wt-02ba4e52389a still 8 ahead; blocker was box load, not a defect or a credential | M |
| `04203db9c27a` | Rule the bottle-service-motion ENTRY treatment (carry = doorway grows into a plate / wipe = no share | TRULY-OPERATOR | value fork — entry treatment, needs an eyes-on round trip | — |
| `0488b0e1e423` | MINT the setup-token canary on next2 — needs a REAL TTY, so Claude Code's `!` prefix cannot do it (s | TRULY-OPERATOR | credential + real TTY + browser identity sign-in before minting | — |
| `07e6e3888e9c` | CORRECTION to this item's own title: the clause 'the 16 existing deploy-parity duplicates were hand- | UNDECIDED | Q: may an agent run the bulk `cc-backlog block` sweep over the 16 named duplicates, or only build the generator re-key? The generator half is agent work; the sweep is classifier-denied | M |
| `0a61d1581a43` | devserver-gc first ARMED run, attended (plist says DEVGC_ACT=1 but launchctl runs=0 — 'armed' is unv | DUPLICATE | survivor 898f8eafb809 — same devserver-gc arming; this row says "close 898f8eafb809 with its verdict" | — |
| `0a9db99fee41` | postgresql@14 has crash-looped every ~10s for 8d21h on a stale postmaster.pid (128 distinct days sin | TRULY-OPERATOR | value fork — is local postgres used at all | — |
| `0eae16398acd` | read the 2 messages dead-lettered from closed duplicate pane 359 — they were DELIVERED but never rea | AGENT-DOABLE | the file exists and is readable: ~/.claude/mailbox/dead-letter/359.md (2157 B) — literally a `cat` | S |
| `10eb9e8c5d0c` | operator decision: real-Azure deploy-orchestrator is a 2-4day effort touching live Azure deploy cred | TRULY-OPERATOR | credential + scope fork — live Azure deploy credentials | — |
| `11dda6f144da` | deploy-live.sh REFUSED at H — 'no GREEN stamp among the newest 200 commits of origin/main'. Pre-exis | STALE | 237ecf2438f9 now ancestor; ~/.claude/bin/cc-offload SYMLINK present | — |
| `137d46537375` | OPERATOR-ONLY CHECK — resolve the Gemini CLI plan tier from an authenticated Google account you own. | TRULY-OPERATOR | credential — resolve the Gemini plan tier from an authenticated Google account | — |
| `1384d3936d7b` | live layer pinned at H with 16 un-stamped commits: postland-verify keeps CUTTING on 'STALL: no TAP p | STALE | live pin 145fab7d2675 now ancestor of 8969739 | — |
| `13e52feb1472` | Set TURSO_AUTH_TOKEN_ASHBURN_GROUP (Turso data-plane group token for the new iad/ashburn-group) in t | TRULY-OPERATOR | credential — mint a Turso data-plane group token for backups/PITR environments | — |
| `158d53aaa3b1` | ratify the armed-succession lifecycle design (kill-by-pid semantics on rails that retire live panes) | TRULY-OPERATOR | value fork — ratify kill-by-pid semantics on rails that retire live panes | — |
| `165acee18b48` | adopt 2 in-flight cloud sessions whose notify-back points at RETIRED pane 104 (fired 2026-08-16T11:4 | TRULY-OPERATOR | known operator-owned (left alone per brief) — adopt or reap two in-flight cloud sessions | — |
| `1684440567db` | REASON PARTLY DISCHARGED 2026-08-07: this item said 'recommend HOLDING until the motion re-haul land | TRULY-OPERATOR | value fork A/B on superseded work | — |
| `180d38b29912` | THREE OPERATOR DECISIONS, all C10, named by the plan's own section 4 (docs/plans/DESK_ROUTER_AND_STA | TRULY-OPERATOR | value fork x3 (D-A/D-B/D-C); accounts[0].launcher measured still 'claude' | — |
| `1858fa6bcbc0` | re-link any Claude account whose CLI→GitHub link is missing, so cloud sessions can be created from i | TRULY-OPERATOR | credential — drives a TUI in a real pane to re-link CLI to GitHub | — |
| `191dbe7e4c42` | motion-plus OAuth for .claude-secondary and .claude-tertiary — each needs ONE consent click from a L | TRULY-OPERATOR | credential — one consent click per config dir from a live interactive session | — |
| `1a003703bc19` | Phone call to Ahmed (not text): 1) does he have pets? 2) is he after a long-term roommate or short-t | TRULY-OPERATOR | human contact — phone call to Ahmed | — |
| `1a4e292830ae` | Wave D — decide the admission-gate terms: admit on ACTIVE concurrency (not load), and replace the me | TRULY-OPERATOR | value fork — admission-gate terms add a REFUSING term to the box-wide spawn path (G2) | — |
| `1be35f0a41dd` | Call T-Mobile National Trial Support 1-833-806-4839 Sun AM (weekend close 3:30pm PST) — ask: check/o | TRULY-OPERATOR | human contact — phone call to T-Mobile support | — |
| `1c5837ed3d34` | Decide which Harbour menu the app should seed: the all-inclusive HARBOUR_2026 (currently seeded, has | TRULY-OPERATOR | value fork — which Harbour menu is current (a business fact) | — |
| `1dca461d4b90` | OPERATOR CALL (web-only, GitHub credentials) — wall RE-VERIFIED 2026-08-13 and the row's PREMISE IS  | TRULY-OPERATOR | GUI + GitHub credentials; the row notes the state may already be resolved, so re-check before acting | — |
| `1e2fdb524533` | Run the staged activation (it is fail-closed and refuses until the fix is deployed): bash ~/.claude/ | TRULY-OPERATOR | C10 — launchctl enable + bootstrap, classifier-blocked to agents | — |
| `1f323187c1e9` | CONFIRM=1 bash ~/.claude/autonomy/pending-activation/10-close-attrib-activate.sh && touch ~/.claude/ | TRULY-OPERATOR | C10 — edits ~/.zshrc and changes how sessions launch | — |
| `216f429128a2` | OPERATOR CALL — wall RE-VERIFIED 2026-08-13 and its STATED BASIS IS PARTLY STALE, corrected here by  | TRULY-OPERATOR | value call — landing into a DEGRADED reso release pipeline; routing note included | — |
| `2203b8190752` | Open https://claude.ai/code/session_01DcTULYmXVnUnrwyFKm8LGH and report what the session shows — did | AGENT-DOABLE | readable via a CDP-attached logged-in browser (autonomous-authenticated-web-access / dia-agent skills) rather than a hand-open | L |
| `24299f47405f` | run /compact-memory on the doc_classifier memory index — MEMORY.md is 20.3KB against a 24.4KB read l | TRULY-OPERATOR | same, for the doc_classifier memory index | — |
| `29d1eba690a3` | wedged owned wait past the 21600s ceiling — live process cwd in /Users/chrisren/Development/.worktre | STALE | worktree wt-29d1eba690a3 does not exist; 0 processes cwd'd there | — |
| `2a51e86b3c79` | Set the iad Soketi env vars on the reso-iad Fly app (and the Amplify/Next build for the NEXT_PUBLIC_ | TRULY-OPERATOR | credential — Soketi app id/key/secret set on a Fly app and the Amplify build | — |
| `2abbe57b5f7c` | Make the L1 death-watch watch-file producer LIVE, then load the watcher — IN THAT ORDER. scripts/dea | TRULY-OPERATOR | C10 — loads a launchd watcher (migration 0004) after linking a live-layer producer; also needs a desk role or CC_DEATHWATCH_WAITER set first | — |
| `2d37bafcf65f` | run migration 0009 to restore the 5 guardrail hooks missing from ~/.claude-next — the unattended-ask | DUPLICATE | survivor 6a428f48fd2e — same migration 0009 guardrail-parity run | — |
| `329dd6350eb3` | cloud create is intermittent: 1 of 4 attempts suH on next3 (2026-08-08), failures fall back to bundl | AGENT-DOABLE | repeat the same cloud-create invocation N times and record the ratio — measurement only | M |
| `35cae65a8d2d` | Operator merges the run-plane loopback fix onto origin/main (this project has NO /ship rail; agent p | TRULY-OPERATOR | doc_classifier has no /ship rail; canonical landing row for the three loopback fixes | — |
| `362fd0c7572f` | postland verifier band: apply the landed plist (H) to the LIVE launchd job — it still carries Proces | TRULY-OPERATOR | C10 — launchctl bootout+bootstrap of com.claude.postland-verify | — |
| `370254a94c83` | Close kitty pane 147 — the wedged M5 session (pid 43305, dead-in-place 3h+, zero children, transcrip | STALE | kitty pane 147 absent; pid 43305 GONE (`ps -p 43305` empty) | — |
| `38b79edd0e90` | BANNER COMPOSITION RULING (Hk #5, live banner): during THE SUMMONING the pair sits 428px right of fr | TRULY-OPERATOR | value fork — banner composition (a) centre the pair vs (b) keep the anchor | — |
| `39045277edc8` | dead-worker stall after 3 dispatch attempt(s) (idle 5596s) — not auto-completable. Investigate, then | AGENT-DOABLE | same class; worktree gone | S |
| `39aae25d401b` | prove cc-relogin phase 2 end-to-end (E3): spends ONE real re-auth, human-gated by design. Phase 2's  | TRULY-OPERATOR | spends one real re-auth; human-gated by design | — |
| `39d8431abae5` | CORRECTED 2026-08-08 — merge target changed AGAIN (third time), same stranding reason this item exis | DUPLICATE | survivor 35cae65a8d2d — identical merge command and target | — |
| `3c6bf04ba842` | NOT an operator step and NOT a defect in this work — parked to keep it out of the dispatch wave. THE | AGENT-DOABLE | its named blocker e280bbc8b6e4 is status=done; branch wt-3c6bf04ba842 is 1 ahead and trunk has it2_run=0 — the land is unblocked | M |
| `3e2358f03e23` | RE-VERIFIED 2026-08-15 — one of the two blockers is GONE and the row is now PARTIALLY DRIVABLE; this | AGENT-DOABLE | the row's own re-verification: 9 flat skills convert today; only the 4 nested ones need install.sh recursion | M |
| `408427e74888` | reconcile ~/.claude/CLAUDE.md with claude-infrastructure/CLAUDE.md — they diverge, and which side is | STALE | `diff ~/.claude/CLAUDE.md <repo>/CLAUDE.md` = 0 lines — IDENTICAL, nothing to reconcile | — |
| `41cea29bfec3` | Operator ruling on approach before any deploy-runner change: (A) instrument Path F (reso-deploy Fly  | TRULY-OPERATOR | value fork — instrument Path F (G2 production runner) vs cosmetic cap | — |
| `42f9772d4b67` | Close husk kitty pane 72 (lakehouse-lecture): its session H was transplanted to next4 and now runs i | STALE | kitty pane 72 absent — `kitty @ ls` now returns windows 2,82,88,100-119 only | — |
| `449f29fad085` | dead-worker stall after 4 dispatch attempt(s) (idle 5524s) — not auto-completable. Investigate, then | AGENT-DOABLE | same class; worktree wt-449f29fad085 no longer exists, so the stall subject is gone | S |
| `475b43aacbf2` | OPERATOR CALL (destructive rm) — wall RE-VERIFIED 2026-08-13 by the local-drain session, independent | TRULY-OPERATOR | destructive rm over 76 orphan worktree dirs, two of which hold live processes | — |
| `488a322b869f` | Studio 60 floor plan V2.4: confirm the 1.29m walkways read right at studio60.localhost:3000/floor-pl | TRULY-OPERATOR | eyes-on confirmation then a production /deploy decision | — |
| `48e14163e78a` | NARROWED 2026-08-15 — the 'live' half of this plan's DoD is now SATISFIED; only the operator decisio | TRULY-OPERATOR | value fork — the same D-A launcher flip; live half of the DoD is already satisfied | — |
| `4a4565d88e81` | converge the live layer — the composer-guard fix is landed on origin/main but ~/.claude/bin/it2-kitt | STALE | ~/.claude/bin/it2-kitty is a live symlink; live HEAD is past ed095d4b | — |
| `4a4b97a2585e` | L1 death-watch is built + GREEN but cannot be activated yet — its watch-file has no producer; the la | DUPLICATE | survivor 2abbe57b5f7c — same migration 0004; 2abbe57b carries the load-bearing ordering | — |
| `4a75a47df016` | teardown 2 orphaned panes + worktrees: pane 379 (desk-w1-routing, task-less INC-4 never-engaged fire | STALE | kitty panes 379 and 376 both absent | — |
| `4c9f2c8a2ec5` | SUPERSEDED — do not build as written; decide its fate. Full analysis landed on origin/main as H (+ . | TRULY-OPERATOR | value fork — retire the item or reverse a shipped design decision | — |
| `4caa5e0beab6` | Close the 10 finished agent panes from session-H (tri-landgate…tri-tail) — each got a reap-guard REA | STALE | the 10 session-e5d3628d agent panes are absent; 16 kitty windows remain, none agent-id | — |
| `504d0bc2fe50` | ARM the read-before-write parity shim as a PreToolUse hook. hooks/lib/read-before-write-parity.sh is | TRULY-OPERATOR | C10 self-modification of the live enforcing layer (PreToolUse hook in every settings.json) | — |
| `5207d553dce2` | READ THIS BEFORE THE TITLE — the title above is WRONG on one point and cc-backlog has no annotate ve | AGENT-DOABLE | the row itself says NOT an operator step; the duplicate-dispatch storm it parked behind is over (0 procs in wt-149789b69fc4) | S |
| `5282f9c30003` | answer the permission prompt in pane 431 (wave-w1-freshness): it has been blocked 1000s+ on 'cd /tmp | STALE | kitty pane 431 absent — nothing left to answer a prompt in | — |
| `52c4a8782157` | TURSO_AUTH_TOKEN_ASHBURN_GROUP is absent from .env.local in BOTH the main reso checkout and worktree | TRULY-OPERATOR | credential — same token, into .env.local on developer hosts | — |
| `5354fffc4079` | deploy-live cannot converge W2's added rail: scripts/cloud-return.sh is on trunk (H) but has NO live | STALE | scripts/cloud-return.sh SYMLINK present in ~/.claude | — |
| `5436396f405c` | sessions are advancing the shared checkout by hand (a raw git pull/merge outside deploy-live) — that | AGENT-DOABLE | the row states the fix is a working-practice/doc change, not a command — a CLAUDE.md/ship-doc edit | M |
| `54b065682a9d` | live layer is 6 commits behind trunk and deploy-live REFUSES to close the gap: it deploys only up to | STALE | live ~/.claude/scripts/limit-recover/lr-fire-resume.sh == trunk (2 hits each, both explanatory comments) | — |
| `54b1c02d7872` | one-time forced advance of the live layer past the green gate — the fixed deploy-live.sh is landed ( | STALE | ed095d4b now ancestor — the one-time forced advance this row asks for has already happened | — |
| `5511ea906e2e` | Live layer is 9 commits behind with 2 ADDED files absent (scripts/mcp-modal-probe.py and its researc | UNDECIDED | Q: is a bare (non-force) `deploy-live.sh` run permitted to an agent? scripts/mcp-modal-probe.py is still ABSENT from ~/.claude and the row is self-described transient | S |
| `564c488fd357` | land the dispatcher ceiling raise (6 -> 12) — committed H on lead/dispatch-ceiling, gate green at 44 | AGENT-DOABLE | commit f420cae62 still reachable as an object; branch lead/dispatch-ceiling + worktree lead-ceiling are gone — re-point and land | M |
| `57c8f9575142` | M7 routing land H goes live only after the in-flight postland-verify corpus run (@H, started ~10:50Z | STALE | live HEAD advanced far past e68b2c32's range | — |
| `5cb75cf245f1` | Delete 3 spent raw-ff scripts from the LIVE ~/.claude layer (C10 — unversioned, unreachable from the | TRULY-OPERATOR | C10 — deleting unversioned files in the LIVE ~/.claude layer in place | — |
| `5fc734347de1` | Re-run /ship when box load < ~8 (it failed twice at load 20-50). Proven not-my-diff: same cls.deck + | AGENT-DOABLE | re-run /ship at low box load; failure was contention, proven not-my-diff | S |
| `62599dd76a60` | pre-existing worktree /Users/chrisren/Development/.worktrees/wt-H is behind origin/main and cannot b | DUPLICATE | survivor 925d843f6665 — same, and it names the 946bdd8dc content | — |
| `6267e2e3c707` | operator decision on HOW to compact: (a) run the human-gated /compact-memory skill and approve its d | DUPLICATE | survivor e27d37eac4cd — same claude-infrastructure MEMORY.md compaction approval | — |
| `6367e1eba8fb` | land BALLAST bottle-service menu deliverable (H) onto origin/main — reso gate: each land bills a rea | AGENT-DOABLE | its cost premise is refuted by sibling 216f429128a2 (Amplify autoBuild FALSE, landing bills nothing) — re-read reso CLAUDE.md then land | S |
| `63929c8d6072` | Run: bash /tmp/bats-dead-assertions-land.sh   (or: scripts/ship-land.sh --trunk main). Work COMPLETE | AGENT-DOABLE | branch wt-63929c8d6072 still 7 ahead; /tmp/bats-dead-assertions-land.sh is gone so run ship-land from the worktree | M |
| `649748653cc5` | Ask KPMG HR/People: which office am I assigned to (Texas vs California), and is there a relocation p | TRULY-OPERATOR | human contact — ask KPMG HR/People | — |
| `66be078a3f50` | OPERATOR DECISION (auth/session escalation surface, CLAUDE.md G2) — may heal() redeem a refresh toke | TRULY-OPERATOR | value fork on an auth/session invariant (G2 escalation surface) | — |
| `6a428f48fd2e` | run migration 0009 (guardrail parity for .claude-next) — the fix is BUILT and staged, only the C10 a | TRULY-OPERATOR | C10 — links hook files and edits settings.json | — |
| `6a8df00b9b52` | run (after 2026-07-21 ~18:00Z, versions aged out): az storage container-rm delete --storage-account  | TRULY-OPERATOR | credential — az subscription-scoped destructive resource-group delete | — |
| `6ae52f7ad4a1` | live layer is 15 commits behind with 42 NEW files unlinked; deploy-live refuses because the newest G | STALE | live HEAD 699bbb743aa2 now ancestor of 8969739 | — |
| `6f54f5c50c2f` | restore the 5 guardrail hooks that .claude-next alone is missing (unattended-ask guard, session-dere | DUPLICATE | survivor 6a428f48fd2e — same migration 0009 guardrail-parity run | — |
| `6f60edde5f59` | Click Continue on the U-Box quote for real delivery fees, re-quote a September ship date, then book  | TRULY-OPERATOR | GUI + payment — book U-Box container, Moving Help, SafeHaul tier | — |
| `7182929f693b` | retire the idle peer pane for backlog item H (work is DONE and landed H) — its self-close was blocke | STALE | backlog item 74a4e3ec3239 reads status=done; the peer pane is gone | — |
| `724a2d2682d5` | rule on heat-v2/b size: 487 net LOC vs the brief's 400 hard cap — the only cut available is provenan | TRULY-OPERATOR | value fork — taste call on provenance prose vs the LOC cap | — |
| `72f5d3842313` | register hooks/goal-inert-watch.sh as a Stop hook so a SKIPPED /goal stops being silent — it edits s | TRULY-OPERATOR | C10 — registers a Stop hook in settings.json | — |
| `733f29225c0c` | Advance the shared checkout so deploy-live can move: git -C $HOME/Development/claude-infrastructure  | STALE | 0 ahead — the reset --hard this row asks for is a no-op now | — |
| `73ce7be9ad31` | converge the live layer onto H — deploy-live.sh declined because no GREEN-stamped tree descends from | STALE | live HEAD 800ea2437257 now ancestor of 8969739 | — |
| `747f2a02641c` | Call Vista Real leasing office: will they permit a U-Box container in the lot during move-out week ( | TRULY-OPERATOR | human contact — phone call to the leasing office | — |
| `7491c15d1e56` | doc_classifier: merge branch wt-H (H) — run-scoped §6.1 blind gate fix, make ci green (4566 passed,  | TRULY-OPERATOR | doc_classifier has no /ship rail; parked on a branch by instruction | — |
| `74e3a245eb85` | ~/.zshrc line ~80 sets CLAUDE_DEFAULT_EFFORT:-max; the Opus 5 re-tier (landing now) makes effort-par | TRULY-OPERATOR | value fork on the operator's own ~/.zshrc default-effort knob | — |
| `75782bed15f8` | reso: run the FIRST /deploy — verifier is GREEN on H (188/188 files, 2139 tests, 150 VRT specs), 28  | TRULY-OPERATOR | agent classifier refuses production deploys | — |
| `777886b8905d` | Request binding quotes from Sherpa + Ship a Car Direct, specifying a Sept 7-8 Austin delivery window | TRULY-OPERATOR | human contact — request binding quotes from two carriers | — |
| `782607797fc5` | Authorize a privileged signal trace to name what is killing the postland-verify corpus. The live lay | TRULY-OPERATOR | sudo — `sudo dtrace` is SIP/root-gated; no unprivileged way to name a signal sender on macOS | — |
| `7903c1f92b76` | the interactive account router is built, tested and landed but NOT wired — wiring it edits ~/.zshrc  | DUPLICATE | survivor b448ceafa0ca — same activation 36-start-latency-router-activate.sh | — |
| `79f6ed72437c` | Ask Narek for the shared-Amazon purchase total and Emilia for the ~$45 Costco salmon receipt — amoun | TRULY-OPERATOR | human contact — ask Narek and Emilia | — |
| `7b4ff0fb1215` | converge the live layer once postland-verify stamps a GREEN tree: deploy-parity-assert exits 1 (name | STALE | 32355a9b1fbe now ancestor; hooks/accounts-board.sh SYMLINK present | — |
| `7c1bfcfa38a0` | 4 orphaned research-subagent processes (land-G1/G2/H/I, ~2.4GB RSS, 16h55m) cannot ack their shutdow | STALE | `pgrep -fl 'land-G1|land-G2'` returns nothing — the 4 orphans exited | — |
| `8177e9ba98e6` | Plug the MacBook into power — reso's design:gate preflight REFUSES on battery, so postland-verify ca | TRULY-OPERATOR | physical — plug the MacBook into power | — |
| `84f053be2850` | arm the fleet inbox by construction: run the c10 migration that registers hooks/mailbox-wake-arm.sh  | TRULY-OPERATOR | C10 — migration edits settings.json in all 4 config dirs | — |
| `85a82455de9a` | resume-sessions still runs the OLD engine: H is landed but NOT live, and its two NEW files have no s | AGENT-DOABLE | 2 of 3 DoD paths now hold (commands/resume-sessions.md SYMLINK, ~/.reso/bin/reso-resume-one now a SYMLINK); only ~/.claude/bin/reso-resume-one is absent | S |
| `85fc4f3216a7` | UNLOAD or properly activate com.claude.auth-timeseries — it is bootstrapped with a MISSING target an | DUPLICATE | survivor e848943a81f4 — same activation 35-auth-timeseries-activate.sh | — |
| `87a515ed087e` | dead-worker stall after 3 dispatch attempt(s) (idle 5542s) — not auto-completable. Investigate, then | AGENT-DOABLE | same class; worktree still present, inspect and unblock | S |
| `88e47aaff3eb` | Pre-grant the tenant-provisioning verb set in .claude/settings.local.json (gitignored, never the tra | TRULY-OPERATOR | permission grant in the operator's own settings.local.json (classifier scope) | — |
| `898f8eafb809` | ARM the dev-server reaper AFTER a few days of clean observe-only verdicts (its own design cadence, n | TRULY-OPERATOR | value call + attended run — the row warns explicitly against arming for the headline number | — |
| `8acb25430a42` | register hooks/mailbox-wake-arm.sh as an asyncRewake SessionStart hook so every session is inbox-arm | DUPLICATE | survivor 84f053be2850 — same migration 0007 mailbox-wake-arm SessionStart registration | — |
| `8c60170a2037` | dead-worker stall after 3 dispatch attempt(s) (idle 5680s) — not auto-completable. Investigate, then | AGENT-DOABLE | auto-filed dispatcher stall; needs no credential/GUI/value call — investigate then unblock | S |
| `8c62c7a963f2` | close peer pane 367E9DA5-E0FF-45A5-9B91-D15BAAA25B14 by hand (iTerm2 ⌘W) — its work is DONE + landed | STALE | iTerm2 UUID 367E9DA5-E0FF-45A5-9B91-D15BAAA25B14 absent from all 16 live it2 sessions | — |
| `8c7f7ae4ee4d` | CORRECTED 2026-08-08 — merge target changed AGAIN, same stranding reason as before. Merge wt-H (H),  | DUPLICATE | survivor 35cae65a8d2d — identical merge command and target | — |
| `8ef642fa78ae` | the live layer (~/.claude) cannot converge past H while no GREEN tree is a DESCENDANT of it — script | STALE | live HEAD 6c5d778b9312 now ancestor of 8969739 | — |
| `8f4eae55a0c7` | OPERATOR CALL — wall RE-VERIFIED 2026-08-13 by the local-drain session: 'gh api repos/renchris/claud | TRULY-OPERATOR | GitHub credentials + a value call on whether signed-commit enforcement should refuse every land | — |
| `903e7ae67621` | advance the LIVE layer: deploy-live REFUSES with NO-GREEN-AHEAD — 'no GREEN tree is a DESCENDANT of  | STALE | live HEAD 6d782c198d9a now ancestor; scripts/cloud-return.sh + gate-red-census.sh are live symlinks | — |
| `925d843f6665` | salvage call on two claude-infrastructure worktrees the dispatcher will now BLOCK instead of thrash: | TRULY-OPERATOR | known operator-owned (left alone per brief) — salvage-or-retire call on two worktrees | — |
| `9381bf26d754` | Rule by eye on two 'What it does' emote candidates before any hero-banner promotion: cut or keep THE | TRULY-OPERATOR | value fork — rule by eye on two emote candidates; no gate can decide it | — |
| `95ea18ea9ac0` | iPhone 16e: cable to Mac, Finder > Back up all data to this Mac, TICK 'Encrypt local backup', record | TRULY-OPERATOR | physical — cable an iPhone to the Mac and tick Encrypt local backup | — |
| `9694e3e863c2` | Order Cox StraightUp Internet (100Mbps down / 5-20 up, overage N/A, $50, modem keep) — serves BOTH l | DUPLICATE | survivor b44d4bbb749e — same Cox StraightUp order, b44d4bbb supersedes with the deadline | — |
| `96fe7b1687a0` | Install the Claude GitHub App on github.com/renchris/claude-infrastructure (GUI consent on your GitH | TRULY-OPERATOR | GUI consent — install the Claude GitHub App on the operator's GitHub account | — |
| `9c5d0ba74e79` | ADDITIONAL EVIDENCE from wt-H (2026-07-26, 4 attempts) — a 4th signal-kill shape to handle, and it i | AGENT-DOABLE | code change to the gate-verdict predicate (read not-ok COUNT never exit code); no credential. NOTE lives in scripts/ship-land.sh which this triage was told not to edit | M |
| `9e2890ff3e1a` | Live ~/.claude layer is 21 commits STALE: the shared checkout ~/Development/claude-infrastructure si | STALE | shared checkout is 0 AHEAD of origin/main — no diverged commits, no destructive history op needed | — |
| `9eab9a51b97f` | Settle wt-pool-1 (branch cc-225947-27025) before any main history rewrite — 39 unlanded commits + 11 | TRULY-OPERATOR | value fork — settle 39 unlanded commits + 11 dirty files before any history rewrite | — |
| `a273a29b9b40` | Amplify console: connect branch 'release', disconnect/disable auto-build on 'main' (app djnbdqpvc08g | TRULY-OPERATOR | GUI — AWS Amplify console branch wiring | — |
| `a3decd2b48dc` | Work phone: Settings > Privacy & Security > Local Network — revoke corporate apps (only channel that | TRULY-OPERATOR | physical/GUI — work phone Settings, on a device no agent can reach | — |
| `a7460321494d` | Decide: renchris/pivot-table-library commits as 'contributors@pivot-table.dev', which GitHub shows U | TRULY-OPERATOR | value fork — is the pivot-table-library commit identity deliberate | — |
| `a7de672c34e3` | CORRECTED 2026-08-07T23:1xZ by pane 667 (pid 12968) — THE PRESCRIBED REMEDY IS INERT; DO NOT RUN IT  | STALE | 0 procs cwd'd in wt-149789b69fc4; the 19-session duplicate population it measures is gone | — |
| `a992a2ba8a83` | Revoke + re-mint the Turso API token 'reso-provisioning' — it was printed into a terminal and transc | TRULY-OPERATOR | credential — revoke + re-mint an exposure-compromised Turso API token | — |
| `ad4743f9ee2c` | dead-worker stall after 4 dispatch attempt(s) (idle 6818s) — not auto-completable. Investigate, then | AGENT-DOABLE | same class; worktree still present, inspect and unblock | S |
| `adf1bb6b5406` | the SessionStart accounts board is landed but reaches no session — settings.json is FIVE separate re | TRULY-OPERATOR | C10 — per-config-dir hook-roster merge across five real settings.json files | — |
| `b09f54e9e080` | RATIFY (once) the C10 rescope that faces 3-4 were built against: 'operator RUNS every activation' be | TRULY-OPERATOR | value fork — ratifying a security-boundary rescope | — |
| `b0a237b76793` | Run docs/activation/pending-activation/32-cc-roles-kitty-normalise-activate.sh (renumbered from 31 — | TRULY-OPERATOR | C10 — staged pending-activation script | — |
| `b2053fe59547` | advance the LIVE layer: the shared checkout ~/Development/claude-infrastructure is 5 commits behind  | STALE | live HEAD 203eb4410301 is an ANCESTOR of current live HEAD 8969739; cc-dispatch symlink live | — |
| `b22e519e06cb` | ROSTER ROW — it holds no work of its own and closes when its members do; every member is now closed  | TRULY-OPERATOR | roster row; every surviving member is an operator step | — |
| `b235198a915f` | Decide /preview/row-alignment: you asked to delete it, but tests/visual/row-alignment.spec.ts drives | TRULY-OPERATOR | value fork — delete the preview route and lose its detector, or keep as fixture | — |
| `b448ceafa0ca` | Activate the interactive account router: claude1 pins account 1, bare claude auto-routes. C10 — edit | TRULY-OPERATOR | C10 — edits ~/.zshrc and flips accounts.json launcher; agent may not self-activate a shell/launcher change | — |
| `b44d4bbb749e` | Confirm Cox StraightUp is ordered + get its activation date — the ONLY open item in the move-connect | TRULY-OPERATOR | human contact + purchase — order/confirm Cox StraightUp | — |
| `b58136d7e4ff` | converge the live ~/.claude layer: scripts/deploy-live.sh REFUSES to advance — no GREEN verifier tre | STALE | live HEAD 56744cfd5b69 now ancestor; scripts/gate-red-census.sh SYMLINK present | — |
| `b5d15c069db3` | Shared claude-infrastructure checkout is behind 67 / ahead 1, so deploy-live REFUSES and 15 landed N | STALE | 0 ahead; ms365 allowlist reached live (`grep -c ms365 ~/.claude/settings.json` = 1) | — |
| `b8270a43d5d9` | AWAITING EMILIA — request already SENT 2026-08-15 19:51 with the exact path (cox.com > My Profile >  | TRULY-OPERATOR | awaiting a third party (Emilia); nothing to draft | — |
| `bbbedc12cb8b` | Rule on ⌘E: keep it bound to open_url_with_hints, or move it behind a chord. You chose ⌘E deliberate | TRULY-OPERATOR | value fork — ergonomics vs mis-hit on the Cmd-E binding | — |
| `bca95577a23e` | live layer cannot converge: deploy-live.sh refuses the advance to H because the shared checkout has  | STALE | shared checkout has 0 dirty tracked files (row measured 25); the peer accounts.json edit is gone | — |
| `bcbc4e714ed5` | ms365 MCP is dead in every config dir: refresh token expired AND the June-2026 personal-account auth | TRULY-OPERATOR | credential — interactive browser OAuth under the consumers tenant | — |
| `bd3a486fa469` | collect the LIVE tengu_prompt_suggestion reason mix: my landed number is a CEILING (67% of typed pro | TRULY-OPERATOR | value call — diverts this machine's first-party telemetry to a local sink | — |
| `c523bfc68ed9` | reply to Zayden Path (Instagram DM) with the join.reso.gl overview link — he asked 2026-08-13 'send  | TRULY-OPERATOR | human contact — reply on the operator's own Instagram DM | — |
| `cb6701bf2217` | SPEC REFUTED + WORK DONE, PARKED ON A FOREIGN TRUNK RED — do NOT re-dispatch this spec. (1) The lint | AGENT-DOABLE | its named blocker 11d3a3cd8507 is status=done; branch 1 ahead, trunk var_default_bins=0 — land it | M |
| `cc48801002bf` | Approve the history-rewrite tool in Bash permissions — the rewrite step is blocked by the auto-mode  | TRULY-OPERATOR | permission grant for a history-rewrite tool — operator's own Bash permissions | — |
| `cf21c910cf9f` | iPhone > Settings > Apps > Messages > Text Message Forwarding > enable this Mac (six-digit code). Me | TRULY-OPERATOR | physical/GUI — iPhone Text Message Forwarding, six-digit code | — |
| `d28f79099ec9` | converge the live layer so the W3 refusal loop actually runs: scripts/cloud-refusal-route.sh is land | STALE | live HEAD e0c6b4e877d7 now ancestor; scripts/cloud-refusal-route.sh SYMLINK present | — |
| `d44857742d3a` | doc_classifier: land branch wt-H (commit H, S4 CH-S DI body-identity fix, make ci green 4570 passed  | TRULY-OPERATOR | doc_classifier has no /ship rail; agent prohibited from landing, and it lands a second commit unasked | — |
| `d5842487233e` | mint a per-routine bearer token (claude.ai/code/routines -> edit routine -> Add trigger -> API; show | TRULY-OPERATOR | credential — per-routine bearer token shown once in the claude.ai web UI | — |
| `d645b199b7b1` | live layer cannot converge: deploy-live.sh refuses because no GREEN tree DESCENDS live HEAD H (newes | STALE | live HEAD 088875158755 now ancestor of 8969739 | — |
| `d7101a81d7d3` | deploy-live REFUSES and the live layer cannot converge: no GREEN stamp among the newest 200 commits  | STALE | postland-verify is stamping (deploy-last-advance 2026-08-16 13:25 to 8969739); live HEAD advanced | — |
| `d8bf32ab63ef` | live layer cannot converge: ~/Development/claude-infrastructure is on main @H, which is NOT an ances | STALE | checkout 0 ahead / main is an ancestor of origin-main again; 4e39debcf no longer diverges | — |
| `d8f8987f79ca` | turn on the assignee-residency alarm AFTER the deploy lands — plist is committed but deliberately ne | TRULY-OPERATOR | C10 — installs a plist and flips its fleet.manifest row | — |
| `d9191f39b5e0` | reap the wedged M5 session: pid 43305 (claude, worktree ~/Development/.worktrees/m5-enforcing-store, | STALE | pid 43305 GONE and worktree ~/Development/.worktrees/m5-enforcing-store no longer exists | — |
| `d9d5b7d97d1a` | unset the stale global git init.templateDir — it points at a DELETED gate-home clone (/var/folders/. | STALE | init.templateDir now = /Users/chrisren/.git-template which EXISTS with hooks/; the deleted /var/folders gate-home path is gone | — |
| `dca44c98f8ac` | Pick a bottle-menu direction: B1 WEIGHT / B2 PRESENT / B3 FILL, all live at localhost:3877/preview/b | TRULY-OPERATOR | value fork — pick a bottle-menu direction by eye | — |
| `dd95e9d5a6c8` | re-run infrastructure/fly-logs-loki-poller/deploy.sh after the Band A A9 commit lands — until then t | TRULY-OPERATOR | production Fly deploy | — |
| `ddb70a52a021` | dead-worker stall after 9 dispatch attempt(s) (idle 5441s) — not auto-completable. Investigate, then | AGENT-DOABLE | same class; worktree gone | S |
| `dea13b7385c5` | Close the orphaned duplicate-worker panes in wt-H BY HAND (this one is fired-peer stamp 499, ~18 mor | STALE | `lsof -a -d cwd -c claude | grep -c 149789b69fc4` = 0 — the ~18 duplicate panes are gone | — |
| `dedd0e256904` | W3 capacity symmetry is landed but INERT on the live box: the diff ADDS scripts/lib/spawn-presence.s | STALE | scripts/lib/spawn-presence.sh SYMLINK present; live HEAD 86e354262d34 now ancestor | — |
| `e09a075539f5` | OPERATOR VALUE CALL — may cc-url-open hold a persistent CDP connection to Dia? A connection-HOLDING  | TRULY-OPERATOR | value fork — security envelope for a persistent CDP connection | — |
| `e2386b169d11` | Allow reading the local WhatsApp ChatStorage.sqlite (classifier-blocked) if roommate chat evidence i | TRULY-OPERATOR | permission grant + a GUI sync of WhatsApp Desktop | — |
| `e27d37eac4cd` | approve the lossy half of /compact-memory for MEMORY.md (26415 B vs the 24985 B loader cap — newest  | TRULY-OPERATOR | approval of the lossy half of /compact-memory (PROPOSE-ONLY by design) | — |
| `e3d8a8cf90a4` | Operator merges the run-plane loopback fix onto origin/main (this project has NO /ship rail; agent p | DUPLICATE | survivor 35cae65a8d2d — the row says "DUPLICATE of 35cae65a8d2d" in its own text | — |
| `e3f988b489c3` | reso soketi-image-cve-scan is a TRUE positive, not noise: green through 2026-06-29, red every week s | TRULY-OPERATOR | value call — a base-image bump on a third-party CVE; alarm should stay red until patched | — |
| `e6240569d6e4` | Complete the 3 pending macOS updates deliberately — the staged payload (since Jul 28) wedged the 8/1 | TRULY-OPERATOR | physical — macOS Software Update + a supervised restart | — |
| `e848943a81f4` | the per-account auth recorder is built + wired but NOT armed — arming it loads a LaunchAgent and nee | TRULY-OPERATOR | C10 launchd load + a hand-run keychain-ACL check from a non-tty context | — |
| `e951f4b9f6e4` | confirm with KPMG whether the agreed '6 hours' includes lunch — decides 09:00-16:00 (re-order the be | TRULY-OPERATOR | human contact — confirm with KPMG | — |
| `eb8911ec044f` | next2 carries a .linked marker but cannot create (falls back to bundle mode) — re-link it | TRULY-OPERATOR | credential — same cloud-websetup TUI drive for next2 | — |
| `ebc271e7f303` | Cursor auto-updates itself in-place (ShipIt) roughly daily while running, and its chrome_crashpad_ha | TRULY-OPERATOR | GUI — Cursor Settings > Application > Update mode, plus a value call | — |
| `ecf9c60083ff` | register hooks/mailbox-wake-arm.sh ALSO on Stop with asyncRewake so an idle session re-arms its inbo | TRULY-OPERATOR | C10 — registers a Stop asyncRewake hook in settings.json | — |
| `eda267ff4b14` | gate bin/reso-resume-one in its own body — H tracked the recovery engine into the repo, which retire | AGENT-DOABLE | pure code: add the capacity term to bin/reso-resume-one; tests/capacity-admit-coverage.bats case 25 already pins the residue | M |
| `ee1ac85c6ff6` | pre-existing worktree /Users/chrisren/Development/.worktrees/wt-H is behind origin/main and cannot b | DUPLICATE | survivor 925d843f6665 — that row is the salvage call covering exactly this worktree | — |
| `eed727ce462b` | decide whether the launchd dispatcher runs with CC_FIRE_CLOUD=on — the pipeline's cron arm fires clo | TRULY-OPERATOR | value call — authorizes autonomous account-quota spend via a launchd env var | — |
| `eefa4bd67ae1` | Sign in to the motion-plus MCP server for CLAUDE_CONFIG_DIR=.claude-quaternary — /mcp -> motion-plus | TRULY-OPERATOR | credential — per-config-dir OAuth consent click for motion-plus | — |
| `f30fa039f98f` | register hooks/coldcompile-admit.sh as a PreToolUse(Bash) hook so cold compiles are admission-serial | TRULY-OPERATOR | C10 — registers a PreToolUse hook in settings.json | — |
| `f3e662d4e2a8` | OPERATOR VALUE CALL — how many concurrent sessions to target, priced as subscriptions: cloud is free | TRULY-OPERATOR | value fork — how many Claude Max subscriptions to authorize | — |
| `f525c9cb7983` | File Apple Feedback for the compressor-segment watchdog panic class (signature is novel per A8 §7: ' | TRULY-OPERATOR | GUI + operator identity — file Apple Feedback | — |
| `f65392a49533` | Rule on B1's travelling tile sheen (keep or cut) — it is the one move its builder flagged as possibl | TRULY-OPERATOR | value fork — keep or cut the travelling tile sheen | — |
| `f89532b8c7f8` | scripts/__tests__/dns-delete.test.ts 'propagates a read failure' is RED on origin/main (blob identic | AGENT-DOABLE | fix scripts/__tests__/dns-delete.test.ts credential-absent path in reso; no live AWS access needed to make it assert correctly | M |
| `fc06e9597fa7` | REASON CORRECTED 2026-08-07: the old 'reso /deploy is operator-only / lands bill a deploy' premise i | TRULY-OPERATOR | value fork A/B/C over a 39-commit range containing a halted wip commit | — |
| `fe74c7c8e83c` | providers.json row for pi-codex is STALE on the live layer: landed H (auth probe corrected to provid | STALE | ~/.claude/providers.json is a live symlink into the checkout and carries the pi-codex row | — |

---

## FLAG A — the DEPLOY / LIVE-LAYER class (the lead asked for this called out separately)

**24 rows describe a landed change not reaching the live `~/.claude` layer.** 21 of them are STALE
snapshots — each named a live HEAD that is now an ancestor of the current one, and each named ADDed
file is a live symlink today. But **the class is LIVE again right now**, and its cause is not
operator-gated:

- Live HEAD `8969739161f1`, **17 commits behind** `origin/main`, shared checkout **0 ahead / clean**
  (so none of the "hard reset" rows applies).
- Newest GREEN stamp is `27772ede4d8d`, **~27 h old** — past the 24 h max.
- The **six most recent postland stamps are all `red` on one and the same failing check**:
  `scripts/subshell-cleanup-lint.sh` (commits `8969739`, `6200a86`, `764f969`, `c037c1a`, `73ceb76`,
  `1c34268`, `1311ba5`); the seventh is `cut`.
- Reproduced here: the lint flags **`scripts/ship-land.sh:3680`** — `BRANCH` assigned inside a `$( )`
  child (`pkt="$(write_decision_packet "$id" "$BRANCH" …)"`, which assigns `BRANCH` at `:584`) while
  the trap `_land_sig_verdict → land_failure_inbox` reads the parent's stale copy at `:813`. The lint
  prints its own prescribed fix.

**So the current deploy blockage has an agent-fixable root cause, not an operator one** — one
subshell-scope fix in `ship-land.sh` unblocks the green stamp, which unblocks `deploy-live`, which
clears the whole class. This triage did **not** touch `ship-land.sh` (out of scope per the brief);
it belongs to whoever owns that file.

The two rows in this class that are NOT stale: `5511ea906e2e` (2026-08-16 — `scripts/mcp-modal-probe.py`
verified **still ABSENT** from `~/.claude`, is on trunk) and `85a82455de9a` (2 of its 3 DoD paths now
hold; `~/.claude/bin/reso-resume-one` is still absent).

## FLAG B — three rows whose own text says they are not operator work

`5207d553dce2` opens *"this is NOT waiting on an operator"*; `3c6bf04ba842` opens *"NOT an operator
step and NOT a defect"*; `a7de672c34e3` corrects its own prescribed remedy to a no-op. All three
were filed `blocked` as a **parking mechanism**, not as an operator gate — `blocked` is the only
state that keeps `cc-dispatch` off a row. That is the mis-filing generator behind most of the
AGENT-DOABLE column: there is no "parked, agent-owned" state, so parking and operator-gating share
one bucket.

## Counts

| Disposition | N |
|---|---|
| STALE | **38** |
| AGENT-DOABLE | **24** (S 11 · M 12 · L 1) |
| TRULY-OPERATOR | **100** |
| DUPLICATE | **15** |
| UNDECIDED | **2** |
| **total** | **179** |

### TRULY-OPERATOR by sub-reason

| Sub-reason | N |
|---|---|
| value fork / judgment call | 34 |
| credential · token mint · browser OAuth · a spent re-auth | 18 |
| C10 activation (launchd · settings.json · ~/.zshrc · live-layer file ops) | 16 |
| GUI-only / physical device | 11 |
| human contact (phone · email · third party) | 10 |
| permission / approval grant in the operator's own config | 5 |
| production deploy, or a repo with no agent land rail | 5 |
| sudo (`dtrace`) | 1 |
| **total** | **100** |

### STALE — the lead may close these 38

```
42f9772d4b67 370254a94c83 4caa5e0beab6 dea13b7385c5 8c62c7a963f2 d9191f39b5e0 5282f9c30003
4a75a47df016 7182929f693b 29d1eba690a3 7c1bfcfa38a0 a7de672c34e3 408427e74888 d9d5b7d97d1a
9e2890ff3e1a bca95577a23e d8bf32ab63ef 733f29225c0c b5d15c069db3 54b065682a9d fe74c7c8e83c
4a4565d88e81 b2053fe59547 903e7ae67621 b58136d7e4ff d28f79099ec9 5354fffc4079 dedd0e256904
8ef642fa78ae 73ce7be9ad31 d645b199b7b1 6ae52f7ad4a1 1384d3936d7b 11dda6f144da 54b1c02d7872
7b4ff0fb1215 d7101a81d7d3 57c8f9575142
```

### AGENT-DOABLE — the 24 mis-filed rows

```
S  8c60170a2037 449f29fad085 ad4743f9ee2c 87a515ed087e ddb70a52a021 39045277edc8
S  0eae16398acd 5207d553dce2 5fc734347de1 85a82455de9a 6367e1eba8fb
M  3c6bf04ba842 cb6701bf2217 02ba4e52389a 63929c8d6072 564c488fd357 eda267ff4b14
M  5436396f405c 9c5d0ba74e79 01ab05685857 f89532b8c7f8 329dd6350eb3 3e2358f03e23
L  2203b8190752
```

### DUPLICATE — 15 rows, with survivor

| duplicate | survivor |
|---|---|
| 8c7f7ae4ee4d · 39d8431abae5 · e3d8a8cf90a4 | 35cae65a8d2d |
| 6f54f5c50c2f · 2d37bafcf65f | 6a428f48fd2e |
| ee1ac85c6ff6 · 62599dd76a60 | 925d843f6665 |
| 8acb25430a42 | 84f053be2850 |
| 85fc4f3216a7 | e848943a81f4 |
| 01288c0aadf2 | 362fd0c7572f |
| 7903c1f92b76 | b448ceafa0ca |
| 4a4b97a2585e | 2abbe57b5f7c |
| 6267e2e3c707 | e27d37eac4cd |
| 9694e3e863c2 | b44d4bbb749e |
| 0a61d1581a43 | 898f8eafb809 |

### UNDECIDED — 2, with the deciding question

| id | question |
|---|---|
| `07e6e3888e9c` | May an agent run the bulk `cc-backlog block` sweep over the 16 named deploy-parity duplicates, or only build the generator re-key? The generator half is ordinary agent work; the sweep is classifier-denied. |
| `5511ea906e2e` | Is a bare (non-`--force`) `deploy-live.sh` run permitted to an agent? Several rows assert agents are classifier-blocked from it *by design* (`deploy-live.sh` line 6); if a plain re-check is allowed, this row is a one-command close. |

## Method notes

- Every STALE verdict is backed by a live read taken 2026-08-16 (process table, `kitty @ ls`,
  `it2 session list`, `lsof -d cwd`, `git merge-base --is-ancestor`, `ls -L` on the live symlink
  path, `diff`), never by a commit subject.
- Two rows named as known operator-owned in the brief — `925d843f6665` and `165acee18b48` — were
  classified but not otherwise examined and were left untouched.
- `pid 12968` (cited by `a7de672c34e3`) resolves today to an unrelated Apple `SandboxHelper`: a
  recycled pid, not the original pane. The STALE verdict for that row rests on the worktree cwd
  census (0 procs), not on the pid.
