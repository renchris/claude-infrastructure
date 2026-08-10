# cluster-P-reso — triage vs `reso-management-app` origin/main @ 55c0c2294

Measured 2026-08-09. Trunk = `origin/main` = `55c0c2294b4c27a22aade10afe3e143ae8785c4d`
(443 commits since 2026-08-01 — this repo moved fast, and most decay in this slice is that churn).
`origin/release` (the ref production actually watches) = `9d22e58cd`, **396 commits behind trunk**.

Read `reso-management-app/CLAUDE.md` first per the task line. Its § Session Close gate-map governs;
its § Quick Commands line 420 is STALE and is itself a finding — see Notes.

## Summary

counts: **PRUNE 21 / UPDATE 11 / KEEP 34 / MERGE 11**  (= 77)

## Verdicts

```
a4514eea7843 | KEEP   | node crash reports still being written: ~/Library/Logs/DiagnosticReports/node-2026-08-09-041046.ips (21 total). Cause still unidentified; doc DoD anchor docs/research/NODE_SEGFAULT_ABRUPT_SESSION_CLOSE_2026-08-02.md present on trunk.
f5882b6d6a8a | KEEP   | verified at source: src/app/api/replicache-pull/route.ts still has `const containerID = process.env.AWS_LAMBDA_LOG_STREAM_NAME || randomUUID()` at module scope; 33 files under src/+lib/ still call randomUUID. ⚠️ A21/Next-16 scope — OPERATOR PRIORITY (Next.js 16.3 upgrade).
bc39703acc44 | PRUNE  | `launchctl list` → `48326  0  com.claude.compressor-sentinel`. The daemon is loaded and running (pid live, last exit 0). ddacadd1 is an ancestor of claude-infrastructure origin/main. Activation done.
a273a29b9b40 | UPDATE | The DISABLE half landed and the release lane was BUILT (fb76c35bb `feat(deploy): release-ref deploy lane`; .claude/commands/deploy.md on trunk). origin/release now exists at 9d22e58cd (item said it was never seeded). What remains unverified from git alone: whether Amplify actually has `release` CONNECTED. Rewrite as "assert the Amplify branch connection via `aws amplify list-branches`", not "seed release".
cc48801002bf | KEEP   | /Users/chrisren/Development/.reso-rewrite-scratch/ still present on disk; classifier denial re-confirmed this turn (my own `git -C <worktree> status` and a credential-store `ls` were both refused). Operator permission still required.
950b7eb56e1f | PRUNE  | all three PIDs gone: `ps -p 56229/40742/68996` → no such process. Panes already closed.
b235198a915f | KEEP   | both halves still on trunk: src/app/(preview)/preview/row-alignment/page.tsx AND tests/visual/row-alignment.spec.ts (+ its snapshot). The delete-vs-keep decision is unmade.
c306d4bc2d2f | MERGE  | canonical = fc06e9597fa7. Same branch cc-225947-27025 (39 unique commits vs origin/main, patch-id count re-measured today). Three items argue one branch's fate.
1c5837ed3d34 | KEEP   | scripts/data/venue-menu-presets.ts, venue-menus-raw.ts and scripts/setup/seed-harbour-bundles.ts all still on trunk; the HARBOUR_2026 vs _SHORTLIST question is unanswered in code.
13ee8c06f088 | MERGE  | canonical = 75782bed15f8. Three separate "run /deploy" rows for ONE fact: origin/release is 396 behind origin/main.
a44eef543cfa | MERGE  | canonical = d56a874d9441. Identical question (does PROD share the caption-vs-figure clock split), filed 8 min apart.
b384effb4100 | KEEP   | FAB_PATTERN appears ONLY at scripts/hooks/pre-commit:63,67. .github/workflows/ holds grafana-validate(.disabled), security-scan, soketi-image-cve-scan, tenant-drift — no fabricated-menu job. The guard still cannot fire on a branch that skips the local hook.
f525c9cb7983 | KEEP   | operator-only (Apple Feedback is a human web form). No refuting evidence available from disk.
ddb70a52a021 | UPDATE | The prescribed fix landed at the WRONG SITE. scripts/postland-verify.sh:271 now runs `pnpm exec next typegen` before typecheck (with the item's own R7 reasoning in the comment) — but scripts/new-worktree.sh still does only `pnpm install --frozen-lockfile` (line 70), and scripts/ship-land.sh:246 still runs a bare `pnpm typecheck` on the land path. Rewrite: the verifier is covered; the PROVISIONER and the land path are not.
d56a874d9441 | KEEP   | verified on trunk: src/components/table-flow/MinimumSpendIndicator.tsx still does `const remaining = Math.max(0, minimum - current)` (~:115) and renders `${formatCents(remaining, currency)} remaining` (~:243) with no animation clock, while 3395bdc57 put motion+ AnimateNumber on every cart money value in the same CartDrawer. Premise intact. (The cited preview fix d73c6088e exists but is NOT an ancestor of trunk; the trunk-landed equivalent is f6576a468, preview route only.)
60a2151c632e | PRUNE  | `lsof -nP -iTCP:3890 -sTCP:LISTEN` → nothing listening. Server already dead.
5fc734347de1 | UPDATE | Blocker premise dissolved by TWO landed commits: 82eb4aeaa `perf(gate): unstarve the design gate — drop taskpolicy -b (measured 18.5x)` and 7906150af `fix(gate): complete LAND_SHIP_V2 — design gate leaves the push path`. The "re-run /ship when load < 8" instruction is obsolete. Branch cc-010333-23674 has grown 25 → **38** unique commits. ⚠️ Platform-page/Miami = OPERATOR PRIORITY (Studio60).
986f6d8f9ce2 | MERGE  | canonical = fc06e9597fa7. Same branch cc-225947-27025.
fc06e9597fa7 | KEEP   | canonical branch-fate item. cc-225947-27025 = 39 unique commits vs origin/main today (unchanged count). Its own NEEDS block already carries the corrected cost premise. The A/B/C fork (autosquash all 39 / land the non-wip prefix / have the heat author finish) is genuinely unmade. ⚠️ Heat venue-landing design — adjacent to the operator's ground-up design track.
1684440567db | KEEP   | cc-135842-3950 = 11 unique commits (matches the NEEDS block's re-measure), branch alive in wt-pool-8. Motion re-haul has landed, so the fork is now purely (A) drop as superseded vs (B) split the named wins. ⚠️ bottle-service = OPERATOR PRIORITY.
085969b7c597 | MERGE  | canonical = cfe6a6fb68fe. Six rows for one file.
cfe6a6fb68fe | KEEP   | canonical memory item, and its number is the only accurate one left: reso MEMORY.md measures **24,367 bytes today** (identical copy in all four CLAUDE_CONFIG_DIRs), i.e. AT the ~24.4KB silent tail-truncation cap. Every sibling row quotes a stale-low size (20.5 / 21.7 / 22.3 / 23.7 / 23.8 KB). Keep this row's guidance verbatim — the propose-only/human-gated half and the "~47% of index lines are the sole home of some fact" warning are the load-bearing content.
eddb9dcda64f | MERGE  | canonical = cfe6a6fb68fe (its 20.5KB is 3.9KB stale).
3824dbfdf50a | MERGE  | canonical = cfe6a6fb68fe (its 24411 B is the closest to today's 24367 B, but cfe6a6fb68fe carries the correct method and the archive-vs-shorten split).
3475190464aa | PRUNE  | the question it exists to settle is answered: studio60 is IN lib/config/tenants.ts:435 on **fly-iad** (104c4f352 `feat(tenants): studio60 joins the fleet on Fly IAD`), and the placement policy landed as 2d6205bb7 per TENANT_PROVISIONING_100P.md:709 ("Fly wins it on the WireGuard intranet"). No RTT sample can now change the region.
e75d0916cc2b | KEEP   | verified: bottle-service-tableside has page.tsx + _ui/ but NO layout.tsx on trunk, and _ui/Tableside.tsx:299 still carries `${GeistMono.variable} ${ROOM_VARS}`. Exactly the state the item describes. Still a live do-it-or-drop-it. ⚠️ bottle-service = OPERATOR PRIORITY.
3b414476d33c | UPDATE | Its sharpest claim is REFUTED: `/deploy` DOES exist — .claude/commands/deploy.md landed in fb76c35bb `feat(deploy): release-ref deploy lane — the one command that spends money`. origin/release has also advanced (0e7dd08 → 9d22e58cd), so "never advanced, watched by nothing" is stale. What survives, and is worse: release is now **396 commits behind main**. Rewrite the item as "production is 396 commits stale and nothing converges it", drop the /deploy-does-not-exist clause. Amplify branch-connection state still needs a live `aws amplify list-branches`.
14e142267a7a | PRUNE  | it exists only as PROOF for 610586f8aeb7, which is dead (see below). A proof of a retired defect retires with it.
41cea29bfec3 | KEEP   | verified: ~/.reso/releases.jsonl has **19 rows, newest 2026-06-26T04:38** (`reso-lax`, manual). scripts/deploy-status.sh:920-925 still computes the Fly cold-build SLO from that local file. Path F auto-deploys still write nothing. The A-vs-B operator ruling is genuinely unmade.
dca44c98f8ac | KEEP   | branch variants-b alive, grown 9 → **29** unique commits vs origin/main. The B1/B2/B3 pick is unmade. ⚠️ bottle menu = OPERATOR PRIORITY.
1925a3a280e4 | PRUNE  | answered by execution, not by probe: TENANT_PROVISIONING_100P.md:709 records `ashburn-group` @ iad created Healthy AND `parent-schema-database-ashburn` created with `Is Schema: Yes` in that NEW group, by the lead against real Turso on 2026-08-08. The grandfathered org can. (The probe would also have been mutating against production — no reason to run it now.)
710523a7b155 | PRUNE  | fixed exactly as prescribed. 9da394a9c `fix(rum): ashburn-group measured every region but its own` re-keyed both maps on `TursoGroup = LocationConfig['tursoGroup']` as an exhaustive Record with an `isTursoGroup` guard and a ternary (not `||`) so an empty list is honoured — the item's own "THE REAL FIX IS THE KEY TYPE" verbatim. rum-latency-http.ts:156 `'ashburn-group': ['turso-ashburn','turso-oregon']`, websocket.ts:207 `'ashburn-group': []` with the empty-host skip the item asked for.
4abcbbbbc997 | UPDATE | branch research/bsm-world-class-gap = 7 unique commits (unchanged), wt-bsm-gap alive. Both stated blockers are now false: landing bills nothing (LAND_SHIP_V2), and the CONTENTION cause was structural — 82eb4aeaa dropped `taskpolicy -b` (18.5x starvation) and 04be75cd6 took design:gate off the land path entirely. Rewrite: this is now an ordinary land, not a "wait for a quiet machine" wait. ⚠️ BSM = bottle-service menu = OPERATOR PRIORITY.
a992a2ba8a83 | KEEP   | token still named `reso-provisioning`, still documented as exposure-compromised at TENANT_PROVISIONING_100P.md:709, no revocation evidence anywhere on trunk. Genuinely operator-only (Turso credential + SSM SecureString). **Highest-severity open item in this slice.**
f65392a49533 | KEEP   | subject lives on branch variants-b (29 unique), not trunk — a single-deletion taste call still unmade. ⚠️ bottle menu = OPERATOR PRIORITY.
04203db9c27a | KEEP   | confirmed OPEN by the plan's own ruling table: docs/plans/BOTTLE_SERVICE_MOTION_GROUND_UP.md:3399 `| W14 entry treatment | STILL OPEN — carry vs wipe | nothing yet; the harness keeps this ONE group |`, and :3444 "the harness survives for exactly it". ⚠️ OPERATOR PRIORITY.
13e52feb1472 | KEEP   | verified: `groupTokenEnvVar()` returns `'TURSO_AUTH_TOKEN_ASHBURN_GROUP'` at scripts/db-backup.ts:66 and scripts/check-pitr-status.ts:59, and db-backup.ts:116 throws `missing ${...}` when unset. Amplify SSM has it (plan:709) but the BACKUP/PITR environments are a different surface. ⚠️ Studio60 = OPERATOR PRIORITY.
2a51e86b3c79 | KEEP   | `SOKETI_APP_HOSTNAME_IAD_INTERNAL` / `SOKETI_APP_KEY_IAD` appear NOWHERE in the tree — they are pure runtime env, so no code change can discharge this. The code legs landed (21cd01850 `feat(infra): fly-iad region config — app + Soketi legs, no spend`; a66995c04 `feat(iad): the region serves`), which makes the silent-degrade-to-public-TLS risk the item names LIVE. ⚠️ Studio60 = OPERATOR PRIORITY.
9eab9a51b97f | KEEP   | wt-pool-1 still exists and still holds cc-225947-27025 (worktree at 2460cb007, branch tip 083b3d03d — so the worktree is itself behind its branch), 39 commits unlanded. The rewrite-orphan hazard stands. (I could not re-count the 11 dirty files: `git -C <worktree> status` was refused by the classifier.) Couple this to cc48801002bf — same rewrite.
97a7e59d310e | MERGE  | canonical = 191dbe7e4c42. Same OAuth, stated generically.
eefa4bd67ae1 | KEEP   | .claude-quaternary unverified — my credential-store read was classifier-refused, and I can only observe the config dir I run in. Unread premise ⇒ KEEP, not PRUNE.
499f6fb39fc1 | PRUNE  | item `1a226422cb37` does NOT appear in backlog-open.json → it is no longer open/blocked. The unblock it asks for is moot.
d88419ba8149 | PRUNE  | its own NEEDS block was the whole item, and that fix LANDED: 82eb4aeaa `perf(gate): unstarve the design gate — drop taskpolicy -b (measured 18.5x)`. scripts/hooks/pre-push:353 now carries the comment "`taskpolicy -b` was REMOVED 2026-08-01 — MEASURED at 11-18x" and defaults to `nice -n 10` (:387), with `taskpolicy -b` reachable only behind an explicit `RESO_GATE_QOS=background`. The VRT half is also discharged: pre-push:348-350 fail-closed-exports PW_BASE_URL (7f5b70039), and 7906150af took the design gate off the push path entirely.
b73444703901 | PRUNE  | fixed, same day, with the item's own measurements quoted back: 3c9ddecdd `fix(bsm): W22 — the header collides on iPhone, and the room was already reserved` — 393px, 35px button overflow, 11px name-over-label confirmed by elementFromPoint, 18.2px at 430, and the W19-shrank-a-ROW critique repeated verbatim. Root cause `min-width:auto` on the flex-item button.
b0be87487228 | KEEP   | verified at source: `'--bs-cap': '148px'` is still a hard literal at _lib/type.ts:287, and _lib/guard.ts:110-140 still asserts captions against it. Fix site unchanged. ⚠️ bottle-service = OPERATOR PRIORITY (but it is a defect, not a taste call).
a4c0c06e0829 | KEEP   | verified BOTH halves: tests/cc-close-attrib.bats:89 still does `mk_stub "$s9" 'kill -SEGV $$'`, and bash crash reports are still landing daily — ~/Library/Logs/DiagnosticReports/bash-2026-08-09-152925.ips, -065607, -050216 (67 .ips total).
54feb11e2537 | PRUNE  | every number is refuted. Live claude-infrastructure checkout: `origin/main..HEAD = 0` (not "diverged by 2"), `HEAD..origin/main = 19`. ba6fb12f IS an ancestor of origin/main, and the LIVE hook ~/.claude/hooks/teammate-auto-shutdown.sh contains `joinedAt` **×3** — the item's own refutation test ("live hook has joinedAt x0 vs origin x3"). The reap fix is running.
414e94838423 | PRUNE  | pid 695 is now `WorldClockWidget` — the Claude session is gone and the pid recycled. (Root cause fd7ba0bbc359 remains open and is correctly a separate row.)
0200998590e7 | PRUNE  | pid 726 gone. Same class as 414e94838423.
1e7a412553ac | PRUNE  | the main checkout is clean (only an untracked probe-tmp.mjs); no heat-v2 direction-B rail-spine change is dirty anywhere reachable. The heat-v2 work consolidated onto cc-225947-27025 — nothing left to commit at this row's granularity.
eb49f2e89e46 | MERGE  | canonical = cfe6a6fb68fe.
abc1143aa2d1 | MERGE  | canonical = cfe6a6fb68fe.
61b8ca278257 | PRUNE  | fixed exactly as the item predicted it would be. scripts/lib/dns-automation.ts now has `findLiveCNAME()` (:166) and deleteDNSRecord's docblock reads "The DELETE payload is built from the LIVE record, never from REGION_TARGETS … The old implementation reconstructed the payload from the region map … so it could only delete records this module had itself written" — the item's own InvalidChangeBatch analysis, landed. verifyDNS returns the live target as S3 promised.
96c57c1c4a6c | KEEP   | verified at source: infrastructure/fly-log-shipper-iad/vector.toml `[transforms.filter_app_logs]` condition is still `.fly_app == "reso-deploy" && includes(["deploy-runner"], .namespace)`. reso-iad app logs would be dropped at the filter. Directory otherwise complete (fly.toml, bootstrap.sh, README, vector.toml). ⚠️ Studio60-adjacent, but it is background observability — safe to fix unattended.
ce2bf742216d | KEEP   | could not refute: there is no `handoff-fire-queue` script in claude-infrastructure origin/main (only scripts/handoff-fire.sh, which has a completion-push.sh hook at :303), and /tmp/fire-wave3.log is gone. Unread premise ⇒ KEEP with a note that the item must name its queue implementation before a session can act on it.
a4860ba27caa | KEEP   | heat-v2 directions b/ and d/ are NOT on trunk (only the single heat route), and `backdropFilter` appears nowhere under the trunk heat route — the finding lives entirely on cc-225947-27025. But the Panda claim generalises: 10+ trunk files use backdropFilter via `css()` (BottleCard, Menu, Scrim, OrderBar, …), so if the finding is right, glass is invisible there too. Worth one browser check on TRUNK before the branch fate is decided.
65818e38e36b | KEEP   | verified at source: heat.css:958-959 is still `:root[data-heat-vt]::view-transition-old(root), :root[data-heat-vt]::view-transition-new(root)` — it overrides `-old`/`-new` and NEVER `::view-transition-group(root)`, exactly the lead the item names. scripts/vt-screencast.mjs still on trunk, so the repro is runnable.
6367e1eba8fb | UPDATE | efb3f4c6b confirmed NOT an ancestor of origin/main (still unlanded, on cc-025105-23721 = 1 unique commit). The item's entire stated blocker — "each land bills a real Amplify Oregon + Fly LAX/SIN production deploy" — is FALSE under LAND_SHIP_V2. Rewrite as a plain land. ⚠️ bottle-service menu = OPERATOR PRIORITY.
875cb1388dba | KEEP   | verified exactly, line for line: lib/rum/useCWV.ts emits `pagePathname: window.location.pathname` at **:68 :102 :181 :212 :239 :269** — the item's six sites, unchanged. `lib/rum/route-pattern.ts` does NOT exist, and `navRoutePattern` appears only in src/instrumentation-client.ts. The mixed-shape PII exposure is live.
09a76d64990d | KEEP   | verified at source: scripts/limit-recover/lr-reset-poller.sh:622 still logs `resume spawn failed (LR_POLLER_SPAWN=$SPAWN_MECH; no GUI and no tmux)` with no retire-or-fix arm. The plist com.reso.lr-reset-poller is loaded (`launchctl list` → `- 0 com.reso.lr-reset-poller`).
191dbe7e4c42 | UPDATE | HALF DISCHARGED, verified LIVE this turn: I am running under CLAUDE_CONFIG_DIR=.claude-tertiary and `mcp__motion-plus__search-motion-source` returned real codex results (accordion → motion://ui/react/accordion et al). **.claude-tertiary is authenticated.** .claude-secondary remains unverified (my credential-store read was classifier-refused, and a session can only observe its own config dir). Rewrite to name only .claude-secondary.
7ad624a26153 | KEEP   | could not refute — the check requires running eslint, which the contract forbids (machine under load) and which needs the fresh worktree's node_modules. What I could confirm: eslint.config.mjs pulls `eslint-config-flat-airbnb` (so import-x arrives via the preset, not a local rule), and `styled-system/**` is a global ignore while tsconfig aliases `styled-system/*`. Premise unread ⇒ KEEP, per the contract's PRUNE-needs-positive-evidence rule.
d83a44fcf68f | PRUNE  | fixed, and locked against regression. scripts/setup/provision-venue.ts:198 now reads "NO `deployTarget` FIELD — deliberately. It used to live here and DISAGREED with…", scripts/lib/dns-automation.ts:40 carries the matching note, and scripts/__tests__/dns-verify.test.ts:58 pins `resolveRegionTarget('oregon') === 'd2cycj6pqx02hg.cloudfront.net'` while :92 asserts the dry-run block contains ZERO `deployTarget:` lines. The dry run can no longer misreport its own effect. (The one surviving `deployTarget: 'unknown'` at provision-venue.ts:2193 is the unrelated report-fallback literal the test deliberately exempts.)
1e6814a4ecdf | KEEP   | verified at source: docs/runbooks/A1_COLDLAUNCH_MONITOR.md:137-138 still reads "BLOCKING: requireRegisteredSpec runs before phase 1 and refuses any --subdomain with no TenantConfig entry. a1probe deliberately has none", and :120 still states the 6-file drift-lint cascade as the reason. The documented Tier-2 workflow still cannot run.
ed724250a9cb | UPDATE | HALF FIXED, and the surviving half is now precisely scoped. eslint.config.mjs global ignores were rewritten with a long provenance comment naming this exact defect ("a blanket ignore made `pnpm lint` green on a diff it had not read a line of") and now un-ignore `scripts/lib` and `scripts/setup/*.pure.ts`. Still ignored: `scripts/checks/`, `scripts/hooks/`, `scripts/data/`, `scripts/__tests__/`, and every operational `scripts/setup/*.ts`. Rewrite: "ZERO coverage" is refuted; the false-pass risk survives for the provisioners themselves and for scripts/__tests__/.
dd95e9d5a6c8 | UPDATE | its PRECONDITION is now met, which flips it from blocked to runnable: 94c0fa24a `feat(obs): gitSha on ssr_timing + doc-metrics through the Fly shipper` landed (the Band A A9 commit). Rewrite: drop "after the A9 commit lands" — just run infrastructure/fly-logs-loki-poller/deploy.sh, and carry forward the warning that it flips ssr_timing ingest on reso-lax/reso-sin from 0 to one Loki line per authenticated document request.
e5d1f1a3f88a | MERGE  | canonical = 75782bed15f8. Its migration detail (0083 guest_claim CREATE, 0084 bottle_order + row_version, the mid-shift stale-IndexedDB edge) must be CARRIED INTO the canonical row — it is the only place that edge is written down, and it is a real deploy hazard.
39045277edc8 | KEEP   | verified live: all six plists still unmanaged in ~/Library/LaunchAgents (com.reso.dead-monitoring, .loki-parity-revisit, .lr-reset-poller, .qa-nightly, .rum-verify-launchflash, gl.reso.csp-smoke, gl.reso.worktree-gc). `launchctl list` shows **com.reso.dead-monitoring at exit status 2** — a currently-failing job — and com.reso.rum-verify-launchflash (the one-shot the item says to retire) still loaded.
75782bed15f8 | UPDATE | canonical production-staleness row, and every number in it is now wrong in the same direction. Measured: origin/release = 9d22e58cd, **396 commits behind origin/main** (item says 28). The verifier-green sha it names (9d22e58c) is exactly what release already carries — so its own action was already taken, and 396 commits have accumulated since. Rewrite against today's tip + a fresh `scripts/postland-verify.sh --status`. Remains genuinely operator-only: /deploy is the one money-spending command (deploy.md frontmatter `disable-model-invocation: true`).
724a2d2682d5 | KEEP   | heat-v2/b is on cc-225947-27025, not trunk; the 487-vs-400 LOC taste call is unmade. MERGE candidate into fc06e9597fa7 if the lead prefers one branch-fate row — kept separate because it is a brief-compliance ruling, not a landing decision.
a8fc24de2909 | PRUNE  | RULED. docs/plans/BOTTLE_SERVICE_MOTION_GROUND_UP.md:3397 — `| W13 card sweep | A — soft · row … | retires variants B C D, the Sweep type, SWEEPS, SweepContext/_lib/sweep.ts, and the sweep group in the harness |`, with :3401 "The sweep ruling is `A`, i.e. the BASELINE WON … Do not re-propose B/C/D." No cardFade/Sweep switch remains under the trunk route.
3b056cc9d9c6 | PRUNE  | superseded by five landed header waves that re-derived the trade from scratch: 4d99e30ba (W23 gap becomes a number), feaa35421 (W24), 3c9ddecdd (W22 collision), plus the operator's own quoted header direction in the plan's ruling table ("make the entire top left content the button with the prefixed '<' … full name of the reservation guest in the header"). The one-line-vs-stacked question this row poses is no longer the question the surface asks.
610586f8aeb7 | PRUNE  | the defect's precondition was removed wholesale. 04be75cd6 `feat(land): v2 fast land lane — lock-free CAS, gate off the land path`: "design:gate leaves the land path entirely (measured 2254s at load 18.78)". scripts/ship-land.sh:12 and :229 now say so in comments, and grep finds no `webServer` / `next dev` / `.next/dev/lock` anywhere in ship-land.sh. With no webServer on the land path, a multi-round CAS cannot collide on one.
6e86209ae6bc | KEEP   | verified at source: scripts/checks/tenant-drift.ts still compares the MANIFEST's `t.dbName` against the live Turso map and against `loc.tursoGroup` — there is no assertion anywhere that the app's connection env var agrees with the manifest. The false-green survives; the runbook mitigation (295df009a, an ancestor) is exactly the "relies on the runbook being followed" the item objects to.
21c6b3ab5532 | PRUNE  | refuted by its OWN evidence field. Its cited sha ad2bd973bdf47 resolves in reso to `docs(research): tmux debug-logging claim refuted — no tmux -v exists on the box`. Re-confirmed live: `ps aux | grep [t]mux` → 0 processes, no /tmp/tmux* dirs. wasDone was already true.
b99fcc4a9db6 | PRUNE  | all three files are ON origin/main: src/app/(guest)/t/[claimToken]/_lib/order.ts, _lib/view-motion.ts, __tests__/order.test.ts. The lead's commit happened.
4c9f2c8a2ec5 | UPDATE | every factual clause is dead exactly as its NEEDS block says, and I confirmed the two checkable ones: ddfec2d08 IS an ancestor of origin/main, and no `vitrine` path exists anywhere on trunk (deleted by 4de135fe2). What survives is ONLY the (a)-retire vs (b)-re-aim-at-tableside fate call — a value judgment on a shipped design decision. Rewrite the item down to that one sentence. ⚠️ bottle-service = OPERATOR PRIORITY.
```

## Master item

One master item only. The other survivors do not join it, and I say why in Notes rather than
manufacturing a second effort out of a list.

### M-reso-1 — every reso gate and monitor either measures what it claims, or says it cannot

**Encompasses:** `ddb70a52a021` · `7ad624a26153` · `ed724250a9cb` · `b384effb4100` · `6e86209ae6bc`
· `96c57c1c4a6c` · `dd95e9d5a6c8` · `39045277edc8` · `09a76d64990d` · `a4c0c06e0829` ·
`a4514eea7843` · `875cb1388dba` · `41cea29bfec3`  (13 items)

**Why this is one effort.** One root cause, stated in this repo's own vocabulary: *a green signal
that was never earned.* Every member is an instrument — a gate, a lint, a drift check, a log
shipper, a launchd monitor, a crash-report stream — that today returns a verdict about a population
it did not read. The failure is always the same shape and always in the same direction (green, not
red), which is why none of them has ever paged anyone:

- **Gates red for a reason outside the diff** — a fresh worktree fails `pnpm typecheck` because
  `next-env.d.ts` was never generated (`ddb70a52a021`) and fails `pnpm lint` on 122
  `styled-system/*` resolutions (`7ad624a26153`). Both convict an innocent diff. This is the
  documented `reference-gate-red-is-usually-the-instrument` class.
- **Gates green over unread files** — `pnpm lint` still skips `scripts/checks/`, `scripts/hooks/`
  and every operational `scripts/setup/*.ts` (`ed724250a9cb`); the fabricated-menu guard lives only
  in a local pre-commit hook so a branch that skips it is unchecked (`b384effb4100`); `tenant-drift`
  validates the manifest's dbName rather than the env var the app connects with, so a post-restore
  repoint passes GREEN while validating a database the tenant no longer serves (`6e86209ae6bc`).
- **Monitors that observe nothing** — the iad log shipper drops `reso-iad`'s own app logs at the
  vector filter (`96c57c1c4a6c`); the Loki poller's namespace entry is inert until its deploy is
  re-run (`dd95e9d5a6c8`); Path F's production deploys write no `releases.jsonl` row at all, so the
  Fly Build SLO panel has been frozen at a 2026-06-26 sample of n=19 ever since (`41cea29bfec3`);
  `com.reso.dead-monitoring` is currently at **exit status 2** and `qa-nightly` fails 13/13
  (`39045277edc8`); `lr-reset-poller` has logged the same spawn failure every 600s for days
  (`09a76d64990d`).
- **An instrument corrupting another instrument's evidence** — and this is the causal link that
  makes the last two members belong here rather than in a separate effort: the
  `cc-close-attrib.bats` fixture does `kill -SEGV $$`, which writes real bash crash reports into
  `~/Library/Logs/DiagnosticReports/` daily (`a4c0c06e0829`), which is **the exact directory the
  unsolved `@libsql` N-API SIGSEGV investigation reads** (`a4514eea7843`, still producing
  `node-*.ips` as recently as 2026-08-09). One of these two items is poisoning the well the other
  drinks from. Fix the fixture first and the segfault hunt gets a clean corpus for the first time.
- **A guarantee that rests on an untested function** — `useCWV.ts` ships a raw `pagePathname` at six
  emit sites while `instrumentation-client.ts` ships a patterned one at four, so `cwv.pagePathname`
  is mixed-shape and half of it leaks tenant-scoped ids (`875cb1388dba`). The PII promise for ten
  beacons currently rests on an unexported, un-importable, untested function — the same "green with
  no measurement behind it" shape, applied to a privacy claim.

**Impact, argued from evidence.**

1. **It unblocks the land rail for every other effort, including the operator's own.** Two of these
   (`ddb70a52a021`, `7ad624a26153`) make a fresh worktree fail gates it did not cause, and
   `ship-land.sh:246` still runs a bare `pnpm typecheck` on the land path. Every dispatched session
   the operator fires for Studio60 or the bottle-service ground-up starts in a fresh worktree, so
   this tax is paid by their work, not just by background work. `ddb70a52a021`'s own history says it
   cost one wasted land round plus a false attribution to an innocent route.
2. **Closing it retires 13 of this slice's 45 surviving items** — the largest single reduction
   available — and it does so without touching a single file the operator's four named efforts are
   editing (see the disjointness argument in Notes).
3. **It is recurring, not one-shot.** `a4c0c06e0829` writes new crash reports *daily*;
   `09a76d64990d` fires *every 600 seconds*; `41cea29bfec3` has been silently blind since June.
   These accrue.
4. **It touches enforcing stores, not documents.** `eslint.config.mjs`, `scripts/new-worktree.sh`,
   `scripts/hooks/pre-commit`, `.github/workflows/`, `~/Library/LaunchAgents/*.plist`,
   `infrastructure/fly-log-shipper-iad/vector.toml`, `infrastructure/fly-logs-loki-poller/deploy.sh`.
   Per the `conclusion-must-reach-the-enforcing-store` class, these are the surfaces where a landed
   change actually changes behaviour.

**DoD.** All thirteen closed, each with its own atomic commit, gates green, landed on `origin/main`
and content-verified (`git ls-tree origin/main -- <paths>`), specifically:

- `scripts/new-worktree.sh` runs `pnpm exec next typegen` during provisioning, with the positive
  control the item names: a freshly provisioned worktree with no `.next/` passes `pnpm typecheck`
  immediately. (Do **not** touch `.claude/settings.json`'s SessionStart hook — C10.)
- A fresh worktree passes `pnpm lint`, or the divergence is diagnosed and written down with the
  reason; either way the close readout can no longer report "trunk lint is red" from a worktree
  artefact.
- `eslint.config.mjs` either lints `scripts/checks/`, `scripts/hooks/`, `scripts/__tests__/` and the
  operational `scripts/setup/*.ts`, or the close readout renders `lint n/a` for scripts-only diffs —
  a deliberate, recorded choice, not a default.
- The fabricated-menu guard runs in `.github/workflows/` (join the existing `tenant-drift.yml`
  pattern), with a red-on-mutation proof.
- `tenant-drift.ts` asserts env-var-vs-manifest agreement, with a fixture that goes RED on a stale
  `dbName`.
- `fly-log-shipper-iad/vector.toml` carries both the runner and the `reso-iad` app (mirror
  `fly-log-shipper-sin`), the app is created, and a log line from `reso-iad` is observed in Loki.
- `fly-logs-loki-poller/deploy.sh` re-run; the `gitSha` join key works outside Oregon.
- launchd: `qa-nightly` green or retired, the raw `&&` escaped in both plists,
  `rum-verify-launchflash` unloaded and removed, `loki-parity-revisit` confirmed, the six unmanaged
  plists repo-ised.
- `lr-reset-poller`'s 600s failure loop fixed or the retry retired.
- The `cc-close-attrib.bats` SEGV fixture no longer writes real `.ips` files (or is annotated so
  crash triage can exclude it), and the `@libsql` segfault investigation is re-run against the
  now-clean corpus with a bounded box.
- `navRoutePattern` + its two tables extracted to `lib/rum/route-pattern.ts`, imported by BOTH
  `instrumentation-client.ts` and `useCWV.ts`, with the closed set unit-tested for the first time.
- `41cea29bfec3` is the ONE member that ends in a filed operator ruling rather than a commit
  (instrument Path F vs recency-cap the SLO window — option A touches the production deploy runner,
  a G2 surface). File it; do not pick it.

**Falsifier** — exit 0 means this whole effort is no longer needed:

```sh
cd /Users/chrisren/Development/reso-management-app && git fetch -q origin && git show origin/main:scripts/new-worktree.sh | grep -q 'next typegen' && git show origin/main:infrastructure/fly-log-shipper-iad/vector.toml | grep -q 'reso-iad' && git show origin/main:scripts/checks/tenant-drift.ts | grep -qE 'TURSO_DATABASE_URL|process\.env\[' && git cat-file -e origin/main:lib/rum/route-pattern.ts && git ls-tree -r origin/main --name-only .github/workflows/ | grep -q 'fabricated\|menu-guard'
```

Five independent conjuncts over five different sub-fixes, all cheap git reads, no network beyond one
fetch, no build. It cannot pass on a partial effort.

**First move.** `bash scripts/new-worktree.sh` a fresh worktree off `origin/main`, then — before
changing anything — run `pnpm typecheck` and `npx eslint src/lib/focus-ring.ts` in it and record
both exit codes. That single act is the positive control for `ddb70a52a021` AND the reproduction for
`7ad624a26153`, it is the cheapest thing in the effort, and it is the one step that must happen
before any provisioning change can be proven rather than asserted. (It is also the only member that
needs a build-adjacent command — do it once, when the machine is quiet, and everything after it is
git reads and edits.)

**Order** (dependency, not priority):

1. `a4c0c06e0829` — stop the bats fixture writing real crash reports. **First**, because every hour
   it runs it adds noise to the corpus step 12 depends on, and it is a small, self-contained edit.
2. `ddb70a52a021` — `next typegen` in `scripts/new-worktree.sh`. Unblocks every later step's
   worktree, and every other session's.
3. `7ad624a26153` — diagnose the fresh-worktree lint divergence, using the worktree step 2 just made
   trustworthy. (Steps 2 and 3 share one control run — do not provision twice.)
4. `ed724250a9cb` — decide and land the `scripts/**` lint scope. Must follow 3: if the fresh-worktree
   lint is broken, widening coverage widens a broken instrument.
5. `b384effb4100` — fabricated-menu guard into CI. Same file family as 4 (`eslint.config.mjs` /
   `scripts/hooks/pre-commit` / `.github/workflows/`), so one owner, sequential.
6. `6e86209ae6bc` — `tenant-drift` env-var assertion. Independent of 2-5; can start any time after 1.
7. `875cb1388dba` — extract `lib/rum/route-pattern.ts`, import from both beacon paths, unit-test the
   closed set. The largest single code change in the effort; touches CWV type contracts and
   `lib/rum/capture-contracts.test.ts`, so it wants its own commit and its own worktree.
8. `96c57c1c4a6c` — `fly-log-shipper-iad` carries the app, not just the runner.
9. `dd95e9d5a6c8` — re-run the Loki poller deploy. **After 8**, so both shipper legs land together
   and one observation confirms both.
10. `39045277edc8` — the launchd sweep (six plists, `qa-nightly`, the raw `&&`, the dead one-shot).
11. `09a76d64990d` — `lr-reset-poller`: fix or retire the retry. **After 10**, because its plist is
    in that sweep.
12. `a4514eea7843` — re-run the `@libsql` SIGSEGV hunt against the corpus step 1 cleaned. **Last**,
    and time-boxed: two negative reproductions are already on record, so treat a third null as a
    result and file it rather than extending.
13. `41cea29bfec3` — file the Path F audit-row ruling (A vs B) for the operator. Last, because it is
    the only member that leaves the effort as a question rather than a commit.

## Notes for the lead

**1. The single most useful thing I found is a stale line in reso's own `CLAUDE.md`, and it is the
generator of five wrong items in this slice.** `reso-management-app/CLAUDE.md:420` still says:

> **Auto-deploy**: push to main → Path F (`reso-deploy` Fly app) ships LAX+SIN; Amplify Oregon
> auto-deploys via webhook.

That is **false under LAND_SHIP_V2** and is directly contradicted by `.claude/commands/deploy.md` on
the same trunk ("Landing is not deploying … `/ship` lands your work on `origin/main` … free,
continuous, builds nothing. `origin/release` is what Amplify and Fly watch"). Five items in my slice
(`fc06e9597fa7`, `1684440567db`, `4abcbbbbc997`, `6367e1eba8fb`, `986f6d8f9ce2`) are parked on the
"landing bills a real Amplify + Fly deploy" premise, and three of them already carry a hand-written
correction in their NEEDS block — i.e. three separate sessions each rediscovered this, individually,
and none of them fixed the source. This is the `resident-policy-must-not-restate-perishable-facts`
class, one layer down: the *project* CLAUDE.md is doing exactly what the global one was rewritten to
stop doing. **Recommend a one-line fix to reso `CLAUDE.md:420` as a standalone commit before any of
these five items is dispatched** — otherwise the next session re-reads the false premise and re-parks.

**2. Operator-priority collisions — 15 items, marked ⚠️ above, deliberately kept OUT of M-reso-1.**

| operator effort | items in my slice |
|---|---|
| Studio60 Miami tenant provisioning | `13e52feb1472` (ashburn group token), `2a51e86b3c79` (iad Soketi env), `1e6814a4ecdf` (a1probe manifest gate), `5fc734347de1` (platform-page/Miami branch), `a992a2ba8a83` (Turso token revoke) |
| Motion Plus MCP bottle-service menu + ground-up design | `04203db9c27a` (entry carry/wipe — plan confirms STILL OPEN), `dca44c98f8ac` + `f65392a49533` (bottle-menu B1/B2/B3 + sheen), `b0be87487228` (`--bs-cap`), `4c9f2c8a2ec5` (vitrine fate), `e75d0916cc2b` (tableside title), `1684440567db` (choreography branch), `6367e1eba8fb` (BALLAST), `4abcbbbbc997` (BSM gap), `724a2d2682d5` (heat-v2/b LOC) |
| Next.js 16.3 upgrade | `f5882b6d6a8a` (A21 randomUUID inventory — it names the Band C / C8 ledger and `docs/plans/_next16_briefs/` exists on trunk) |
| guestlist → SevenRooms pipeline | none in this slice |

Two of these are worth flagging up to the operator rather than just parking:

- **`a992a2ba8a83` is the highest-severity open item in the whole slice** and it is a *security*
  action, not a design one: a full-Platform-API Turso token covering every tenant database was
  printed to a terminal and transcript on 2026-08-08 and has not been rotated. Under the global
  protocol's "security / data-integrity → stop-surface now" rule this outranks its Studio60
  adjacency. It is genuinely operator-only (credential).
- **`04203db9c27a` is confirmed open by the plan's own ruling table, not by inference** — line 3399
  literally reads `STILL OPEN — carry vs wipe`, and line 3444 says the whole variant harness survives
  for exactly that one question. If the operator wants the harness deleted, this is the one ruling
  standing in the way.

**3. Disjointness of M-reso-1 from the operator's tracks — argued, not assumed.** M-reso-1's file
footprint is `scripts/new-worktree.sh`, `eslint.config.mjs`, `scripts/hooks/pre-commit`,
`.github/workflows/`, `scripts/checks/tenant-drift.ts`, `lib/rum/{useCWV,route-pattern}.ts`,
`infrastructure/fly-log-shipper-iad/`, `infrastructure/fly-logs-loki-poller/`,
`~/Library/LaunchAgents/`, `scripts/limit-recover/`, `tests/cc-close-attrib.bats`. The operator's
tracks live in `src/app/(preview)/preview/bottle-service-*`, `src/app/(guest)/t/[claimToken]/`,
`lib/config/tenants.ts`, `scripts/setup/provision-venue.ts`, and the Next-16 briefs. **Zero shared
files.** The one genuine adjacency is `96c57c1c4a6c` (the iad log shipper is Studio60 infrastructure)
— but it is deploy-side observability with no code the provisioning track touches, so I kept it in
and note it here rather than splitting the effort around one file.

**4. Cross-cluster duplicate risk — check before you merge.** Eight items in my slice are filed
`project=reso` but their SUBJECT is claude-infrastructure, so they very likely have twins in the
`cluster-C-*` slices: `bc39703acc44` (compressor sentinel — I PRUNEd it, daemon is running),
`54feb11e2537` (live-checkout drift — PRUNEd, refuted numerically), `21c6b3ab5532` (tmux — PRUNEd by
its own evidence commit), `ce2bf742216d` (handoff fire queue), `09a76d64990d` (lr-reset-poller),
`a4c0c06e0829` (bats SEGV fixture), `a4514eea7843` (libsql segfault), `f525c9cb7983` (Apple
Feedback). **If a C-cluster agent KEEPs one I PRUNEd, mine is the one measured against live process
state today — but reconcile explicitly rather than taking either on faith.** Same warning for the six
MEMORY.md rows: `cluster-C-memory` may hold the claude-infrastructure equivalents, and the two files
are different objects with different sizes (reso's is 24,367 B; claude-infrastructure's own index
already prints its over-cap warning in this session's context).

**5. Three items I could not fully verify, and I am saying so rather than guessing.**
`7ad624a26153` (needs an eslint run — forbidden by the contract's load rule), `eefa4bd67ae1` /
`191dbe7e4c42`-secondary (needs a credential-store read — refused by the auto-mode classifier), and
`9eab9a51b97f`'s dirty-file count (`git -C <worktree> status` — also classifier-refused). All three
are KEEP-with-note per "an unread premise is *I could not tell*, not *it is finished*". Worth knowing:
**the classifier refused three read-only commands during this triage** (`git -C <path> status`, a
`ls`/`python3` read of `.credentials.json`), which is the same friction `cc48801002bf` and
`499f6fb39fc1` are filed about. If the lead is already touching Bash permissions, `git -C <path>
status` is a safe read-only addition that would have removed one of my blind spots.

**6. Landing policy for whoever fires M-reso-1.** reso's project `CLAUDE.md` § Session Close says
"Push / ship = `/ship`, your explicit call" — but that clause predates LAND_SHIP_V2, and
`.claude/commands/deploy.md` establishes that `/ship` is now free and `/deploy` is the only
money-spender (`disable-model-invocation: true` in its own frontmatter). Under the global ship-policy
table, "the repo's own CLAUDE.md says landing spends money" is **no longer true of `/ship` here**, so
M-reso-1's commits should auto-`/ship`. **`/deploy` must never be fired by an agent** — item
`75782bed15f8` stays operator-only, and the correct disposition for the 396-commit production lag is
FILED (`cc-backlog needs`), never DRIVEN. Gate names for the effort: `tsc --noEmit` + staged `eslint`
at commit time; `pnpm test:unit` when `src`/`lib`/`replicache` changed; `pnpm design:gate` only if
`src/app/(preview)/`, `tests/visual/` or `docs/design-targets/` changed — **M-reso-1 touches none of
those, so design:gate is `n/a` for the entire effort**, which is a large part of why it is safe to
run unattended on a loaded machine.
