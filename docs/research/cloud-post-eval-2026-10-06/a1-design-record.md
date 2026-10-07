# A1 — Cloud backlog lane: current design, status and standing verdict (as of 2026-10-06)

Subject repo: `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` (HEAD `593a21fc3`, itself a cloud-session landing dated 2026-10-06). Read-only throughout. Paths below are relative to that repo unless absolute. "Measured" = a command I ran today (listed in §9); "documented" = stated by a dated repo source; "inferred" = my reasoning.

## 0 · Status in one table

| question | answer | basis |
|---|---|---|
| Running? | **Yes, live and firing today.** 2 fires on 2026-10-06 (10:58Z, 16:41Z), both returned and landed; lane tick at 2026-10-07T02:05Z reads `LIVE — last fire 9.39 h ago` | measured: `~/.claude/autonomy/cloud/*.decl` fold; `~/.claude/logs/cloud-return-lane.log` tail; `git show 593a21fc3 c2c1660e4` |
| Paused / retired? | **No.** `CC_FIRE_CLOUD=on` in live dispatcher and sweep plists; live plist byte-identical to `launchd/com.claude.dispatcher.plist`; both jobs loaded | measured: `plutil -extract ProgramArguments.2 raw`, `diff -q`, `launchctl list` |
| Shrunk? | **Yes, emergently, not by ruling.** 30–55 fires/day (08-24→09-04) → 1–6/day since 09-07 → **31 fires in the 15 days since 09-22 (2.1/day; 6 zero-fire days)** | documented: `docs/research/backlog-drain-audit-2026-09-22/a2-cloud-lane.md:268-269`; measured: decl fold |
| Redesigned? | **No.** The 09-10 "split" redesign was refuted on cost and not built; what changed since is repair-in-place of the return arm | documented: `docs/research/cloud-lane-redesign-2026-09-10.md:309-318,370-371` |
| Standing verdict | **09-10 RETIRE@70% is superseded.** Packet `663522aa67b1` was closed `actioned / SUPERSEDED` on 2026-09-23T01:56:03Z by `7960dccd172f`: *"Keep it and fix it in place"*, conviction 70, class C, **still OPEN** (operator has not ruled) | measured: `~/.claude/autonomy/decisions/{663522aa67b1,7960dccd172f}.json`; documented: `git show caacebf1e:docs/research/decision-consolidation-2026-09-22.md:23,70` (file removed from HEAD 2026-09-26) |

## 1 · Architecture end to end (as built today)

| stage | mechanism | where | dated |
|---|---|---|---|
| 1 Label | `bin/cc-venue` writes `venuePlan`/`venueWhy` on open rows; decision = `bin/cc-eligible` spelling classes + a measured history arm (cited sha inside newest 50 commits) + `certify()` + `cc-premise`. Producer fails CLOSED (any uncertainty → local); a shallow clone cannot mint a cloud label | `docs/plans/CLOUD_BACKLOG_PIPELINE.md:450-473` | 2026-08-11 |
| 2 Select | launchd `com.claude.dispatcher`, 300 s, `cc-dispatch --once`, `CC_DISPATCH_PROJECT=claude-infrastructure`, `CC_FIRE_CLOUD=on`. Selects `status=="open"` only. Cloud-specific gates: pile cap 50 unlanded declarations (`bin/cc-dispatch:455,2158-2174`); already-declared gate, one unlanded session per item (`:2187-2198`); opt-in check, else the cloud-planned row fires LOCALLY (`:2843-2846`) | live plist argv (measured); `backlog-drain-audit-2026-09-22/README.md:15` | 2026-09-22 / today |
| 3 Brief | Composed by the dispatcher; cloud variant swaps rails: "commit on THIS branch and PUSH; do NOT /ship, do NOT land" (`bin/cc-dispatch:3084`); BOOT PING `git push -u origin HEAD` as first act (`:3207`); staleness rail: `git fetch --unshallow` before any trunk read (`:3210`); three terminal dispositions routed through the branch — work, verdict artifact `docs/research/*.md`, or `scripts/cloud-park.sh <id> --needs` (`:3235-3237`) | `bin/cc-dispatch` | 2026-09-02 |
| 4 Create | `cc-offload up --via api --task <brief> --account <routed> --item <id>` (`bin/cc-dispatch:3432-3435`). Account from `claude-accounts --route general`; branch `claude/fire-<UTC>-<pid>-<n>`; `scripts/cloud-create-api.py` does a two-call create (resolve `anthropic_cloud` environment, then `POST /v1/sessions` with `environment_id` + one `git_repository` source, header `anthropic-beta: ccr-byoc-2025-07-29`) and exits 5 unless read-back shows `environment_kind: anthropic_cloud` AND exactly one source | `bin/cc-offload:680-730`; `scripts/cloud-create-api.py:1-75` | 2026-08-10 |
| 5 Declare + custody | `cc-cloud declare` (id, branch, account, item, notify-back, custody) BEFORE delivery; `cc-custody open` at the fire so a close during flight is impossible | `bin/cc-offload:722-751` | 2026-08-11 |
| 6 Deliver | Brief is NOT in the create. Boot contract (`scripts/lib/cloud-create.sh:280-302`) is prepended and sent with `claude -p "<msg>" --cloud <id> --output-format json` via `cc-notify --cloud`, using the launcher-pinned binary | `bin/cc-offload:764-766`; `bin/cc-notify:111-135` | 2026-08-08 |
| 7 Work | Firecracker microVM, `/home/user`, depth-50 clone of ONE repo, no `~/.claude`, reclaimed at session end; pushes to its declared branch only | `CLOUD_BACKLOG_PIPELINE.md:101-116` | 2026-08-10/11 |
| 8 Observe | No VM→box channel. `git ls-remote` polling + control-plane read (`worker_status`, `post_turn_summary`). RETURN-READY = pushed AND worker not running AND sha quiet 180 s (`worker_status: idle` alone proves nothing) | `CLOUD_BACKLOG_PIPELINE.md:208-217`; `docs/plans/CLOUD_OBSERVABILITY.md:86-97,197-209` | 2026-08-11 |
| 9 Return | launchd `com.chrisren.autonomy-sweep` (300 s, `taskpolicy -c utility`) detaches `scripts/cloud-return-lane.sh`: fire-lane read → RETURN (bound 5,400 s) → RETIRE (900 s) → ANSWER (300 s) → RESCUE (5,400 s), single-flight lock | `scripts/cloud-return-lane.sh:1-75`; `CLOUD_BACKLOG_PIPELINE.md:1505-1515`; commit `3650c703b` | 2026-09-06 … 09-30 |
| 10 Land | `cloud-return.sh` → `cloud-reconcile.sh --land` → `desk-land.sh` → `ship-land` (full gate ON THE DESK, behind the shared land lock). VM commits are authored `noreply@anthropic.com`, re-authored as the operator with `Cloud-session:` / `Original-commit:` / `Original-branch:` trailers; verified BY CONTENT, never by sha | `scripts/cloud-return.sh:53,756`; `CLOUD_BACKLOG_PIPELINE.md:51-61` | 2026-08-11 |
| 11 Close | Step 8: landed content → `cc-backlog done`; a landed `docs/parks/<id>.md` whose `branch:` matches → `cc-backlog block`; custody discharged; wake to the stamped pane, falling back to `--role desk` | `CLOUD_OBSERVABILITY.md:2001-2003,2050-2067`; `CLOUD_BACKLOG_PIPELINE.md:1525-1528` | 2026-08-26/29, 09-06 |
| 12 Side arms | Refusal loop `cloud-refusal-route.sh` → `cc-offload say` (a gate refusal reaches the VM; demonstrated 56 s turnaround); `cloud-retire-terminal.sh` verdicts `gone/landed/superseded/conflict`; `cloud-inbox.py` reads asks, `cloud-answer.py` FILES a `cc-do` row and never executes VM text; `cloud-reconcile.sh --rescue-docs` lands add-only `docs/` files from retired/undeclared branches ≥12 h old; `branch-prune-landed.sh`; `cloud-lane-liveness.sh` | `CLOUD_BACKLOG_PIPELINE.md:502-507,1520-1524,1655-1685`; commits `f79d58a7f`, `4595b8a34`, `8a2a9acda` | 2026-08-11 … 09-30 |

Size: lane scripts + bins = 17,435 lines across `bin/cc-{dispatch,offload,cloud,venue,eligible}` and `scripts/cloud-*` (measured, `wc -l`; `cc-dispatch` 4,221 of those is shared with the local lane). The 09-10 memo counted 20,167 with tests (`cloud-lane-redesign-2026-09-10/LEAD-notes.md:9`).

Plan-of-record pointers: `docs/plans/BACKLOG_DRAIN_24_7.md:1-5` (`status: open`) declares itself SSOT and "supersedes-for-operation" `CLOUD_BACKLOG_PIPELINE.md`, whose "architecture remains the cloud-lane reference"; Lane A definition at `BACKLOG_DRAIN_24_7.md:32450-32463`. `CLOUD_BACKLOG_PIPELINE.md:2` says `status: complete` (see §6 disagreements). `CLOUD_OBSERVABILITY.md:2` is `status: open`.

## 2 · What the two named studies concluded

### 2026-09-10 redesign campaign (`docs/research/cloud-lane-redesign-2026-09-10.md`)

| finding | value | line |
|---|---|---|
| Conviction | RETIRE 70% (below the 90% implement bar); filed as class-C packet `663522aa67b1` with options retire / repair-narrow / redesign-split | 9, 363-372 |
| Feasibility | Not impossible: 93.4% of stranded branches merged clean at push, 90.0% at +1 h, 69.3% at +24 h, 28.1% at +7 d, 5.5% "today"; median lag push → first land event 207 h | 91-102 |
| Why the yield was 12.8% | Return arm capacity-starved: 25 of 25 land invocations since 09-08 `exit:143` at the lane's own 5,400 s bound; cold `git worktree add` per land (p50 870 s vs 340 s warm); STALE-GATE livelock P(round survives) ≈ 4% | 133-154 |
| Purpose refuted | "Capacity valve": cloud draws the SAME Max quota (vendor-stated + Fisher p = 6.5e-06) and machine capacity did not bind the local dispatcher (0 rc-9 refusals over 297 fires) | 180-197, 219-240 |
| Reach | Flow is wide: 60% of the real-fix flow is split-reachable; classifier admits 10.2% and is 62.5% false-negative over its refusals; `ineligible-box` is 54% of flow and 20 of 27 sampled are reachable | 55-63 |
| Cost | Per fire cloud $5.63 vs local $21.38 (mean); per landed row $43.80 vs $31.67 (7.78 vs 1.48 fires per landed row); with re-fires gated and landings restored, projected $5–6 vs $18 | 205-217 |
| Work quality | 108 sessions with content on trunk, zero reverts / re-lands across 112 landed shas; 44% docs-only; 68% of docs output was the lane reporting its own mis-dispatch | 246-258 |
| Trust boundary | 131 remote-authored commits re-authored as the operator; every widening (repos, gh, browser) widens an unreviewed remote author's reach | 269-273 |
| Redesign-split | Refuted: VM cannot pre-run a useful part of a land (statics+smoke ≈ 0.1% of wall); cloud-claimed "real fix" 3.7× likelier to be a docs artifact (48% vs 13%) | 309-318 |
| Off-box gate (GitHub Actions) | Refuted: 0 of 428 gated trees overlap a stamped tree; memoize ratchets instead | 392-405 |
| Follow-ons executed 2026-09-11 | Harvest: 7 shas landed (trailer-stripper `e49308b92` first); local-lane fixes 3 of 4 landed; pane-anchor defect left to operator (`e04168383cd6`) | 407-455 |
| Retire must be sequenced | Already-declared gate has no TTL: stop the retire pass first and 6 rows never fire in either lane | 283-293; `…/W2-red-team.md:9,26` |
| Devil's advocate | 80 → 70: genuine lane-machinery rows 2.9% not 10%; repair-narrow = 4–10 rows/day; 202–253 pp quota stranded at 09-05/06 resets | `…/W2-devils-advocate.md:15-23` |
| Lead hypotheses | H1 loss is return latency; H2 VMs add machine capacity only; H3 off-box gate (later refuted); H4 supply bounds cloud at ~2 fires/day | `…/LEAD-notes.md:21-25` |

### 2026-09-22 drain audit (`docs/research/backlog-drain-audit-2026-09-22/`)

| finding | value | line |
|---|---|---|
| Verdict | Cloud lane is alive and **the most productive of three lanes**: 116 distinct rows landed on `origin/main` over 45 d (floor 85, classifier 105); 2.6 rows/day lifetime, 1.4/day last 14 d | `README.md:38-44`; `a2-cloud-lane.md:9-27` |
| Leak is waste, not loss | 545 of 727 declarations (74.9%) re-fired an item already out; worst item ×38; session yield 20.5% of fires | `a2-cloud-lane.md:30-34,53,75` |
| Queue | Dispatchable cloud queue = 0: all 28 eligible rows were `blocked`; none of 10 open rows eligible. Eligible 8.0% of 350 non-done (was 14.4% on 08-11); new class `ineligible-cross-repo` = 84 rows | `a2-cloud-lane.md:184-216` |
| Pile cap | "332 unlanded vs cap 50" NOT in force: 0 pending; it held 58.8 h (09-04T19:38Z → 09-07T06:23Z) | `a2-cloud-lane.md:115-139` |
| Liveness sensor | `cloud-lane-liveness.sh` permanently VOID since 09-16 (pinned floor 426 vs 334 after pruning) | `a2-cloud-lane.md:141-180` |
| Best case latency | add → landed → closed in 46 min (`187ee2cb4252`, 2026-09-22) | `a2-cloud-lane.md:223-236` |
| Classifier blind spot | `cc-cloud landed()` is "not landed" on empty `paths=`; 598 of 727 declarations had empty paths, so STALLED is mostly decay | `a2-cloud-lane.md:94-109` |
| Design record | `CC_DISPATCH_VENUE_ONLY=cloud` is NOT on the live daemon (un-parked 09-07); routing last 2 d was 45 local / 9 cloud; `CLOUD_BACKLOG_PIPELINE.md status: complete` "REFUTED by an open operator decision" | `a6-design-record.md:52,96,164-174` |
| Human in the loop | Two condition-keyed cloud-session rows took 65 block events in September across 8 sessions, each stalled on a permission grant or a question answerable only in the cloud web UI | `README.md:114-118` |
| Cost | Not computable (the `cc-quota-price` bucket defect); the earlier $3.35/closure figure is off-currency | `README.md:164-166` |
| Quota | Last 7 resets all 100% used: opportunity cost is 1:1 | `README.md:138-143` |

Intermediate, same question: `docs/research/drain-pipeline-productivity-2026-09-16.md:18-21,55-61,282-307` found both lanes stopped; the cloud lane was dark 2026-09-11T23:20Z → 09-16 because `cloud-create-api.py:183` read the keychain without `-a` (719 abstains, 0 returns); fixed `6ff54011b`. It priced cloud at $32–112 per closure and called landing latency "the single highest-leverage cloud fix".

## 3 · State measured today (2026-10-06 / 2026-10-07T02Z)

| metric | value | command |
|---|---|---|
| Declarations all-time | 757 (first 2026-08-08, last 2026-10-06T16:42Z); 0 pending (none lacks both `.returned` and `.retired`) | python fold of `~/.claude/autonomy/cloud/*.decl` |
| Fires since 09-22 | 31 over 24 distinct items (max 3 fires on one item); per day 5,6,0,3,2,0,5,0,0,3,2,0,3,0,2; accounts next4 11 · next 9 · next2 6 · next3 5 | same |
| Returned since 09-22 | 23 of 31 carry `.returned` (74%). `.retired` verdict field across the 31: none 19 · conflict 5 · superseded 4 · gone 2 · landed 1 (a session can carry both a verdict and `.returned`; all five 09-28 fires do) | same |
| On trunk | 26 distinct sessions with fire date ≥ 09-22 carry a `Cloud-session:` trailer on HEAD (84% of 31): 9 code-bearing, 17 docs-only = 5 parks + 6 already-cured verdicts + 4 doc-rescues + 2 other | `git log --since=2026-09-20 --grep='Cloud-session:'` + `git show --name-only` |
| All-time trunk | 250 `Cloud-session:` commits, 182 distinct sessions | `git log --grep='Cloud-session:'` |
| Fire → returned latency | n=23: min 1,499 s · p50 6,307 s (1.75 h) · p90 22,060 s (6.1 h) · max 206,574 s | `.returned` mtime − `declared_at` |
| Land cost on the desk | n=26 since 09-22: median 1,205 s · p90 2,467 s · max 5,254 s | `*.land-cost` |
| Land refusals since 09-22 | 9 artifacts: rc 2 ×3 (the outer-timeout preflight), rc 6 ×6 | `*.land-refused` |
| Backlog | 4,241 items: 4,120 done · 120 blocked · **1 open** (was 350 live / 10 open on 09-22). Live `venuePlan`: 2 cloud (blocked), 25 local, 94 unset | `bin/cc-backlog list --all --json` |
| Venue routing since 09-22 | 220 events: 32 cloud (14.5%) · 188 local, of which `ineligible-box` 156, `cross-repo` 9, `deep-history` 9, `spawn-rail` 6 | fold of `backlog.jsonl` `event=="venue"` |
| Lane share of closes since 09-22 | 793 `done` events; 35 cite a cloud session (4.4%); `lane:"cloud"` 10 | fold of `backlog.jsonl` |
| Lane tick | return 3 s, retire 9 s, answer 0 s, rescue 36 s, "no MANAGED cloud declarations" (idle) | `tail ~/.claude/logs/cloud-return-lane.log` |
| Binary | Launcher pin = `~/.claude-284` (2.1.284, dir created 2026-09-28T13:48 CDT); today's fire has a `kind:"cloud-send"` sidecar and returned | `bin/cc-claude-bin`; `claude --version`; `session_01QBCkf55RXXM5ZHmstwr1JV.sends` |

Inference from these rows: session-level conversion rose from 12.8–20.5% (August–September cohorts) to 74–84% in the post-09-22 cohort while volume fell to ~2 fires/day; the already-declared gate (`124c4da06`, cited at `cloud-lane-redesign-2026-09-10.md:167-168`) and the dedicated lane tick are the documented mechanisms, but no source attributes the improvement causally. Supply now bounds the lane: 1 open row, 14.5% of routing events admitted.

## 4 · Constraints stated as binding

| constraint | consequence in the design | source (date) |
|---|---|---|
| Clone is shallow, depth 50 | Ancestry/blame/`log` answer wrong silently; brief mandates `git fetch --unshallow` first; `git rev-parse --is-shallow-repository == false` is the only admissible precondition for a provenance answer. `CLOUD_DEPTH = 50` still in the classifier | `CLOUD_BACKLOG_PIPELINE.md:104-106`; `CLOUD_OBSERVABILITY.md:2186-2194` (09-03); `bin/cc-eligible:759` |
| `~/.claude` does not exist in the VM | `cc-backlog`, `cc-notify`, `cc-bats`, `/ship` are no-ops off-box; backlog store is machine-local; claim locally before firing; the branch is the ONLY channel back | `CLOUD_BACKLOG_PIPELINE.md:113-116`; `bin/cc-dispatch:3235-3237` |
| `~/.claude` must NOT be provisioned into the VM | A snapshot hands the VM "a plausible-looking empty version" — the anti-goal | `CLOUD_BACKLOG_PIPELINE.md:867-872` (08-11) |
| One repository per session | `sources[]` authorizes the git proxy; other repo → 403. Every non-`claude-infrastructure` row is structurally unexecutable; class `ineligible-cross-repo` | `CLOUD_BACKLOG_PIPELINE.md:1399-1401`; `BACKLOG_DRAIN_24_7.md:32580-32593`; `bin/cc-eligible:495` |
| No VM → box push; no inbound channel | Return arm is polling; absence is ambiguous without the boot ping; do not try to symmetrise | `bin/cc-offload:46-49`; `CLOUD_OBSERVABILITY.md:142-151` |
| The VM cannot land | Every return costs a full `ship-land` gate on the desk behind the shared land lock; pre-runnable fraction of a land ≈ 0.1% | `cloud-lane-redesign-2026-09-10.md:143-149,268-270` |
| VM identity | Commits arrive as `noreply@anthropic.com`; identity gate refuses on purpose; re-authored as operator with provenance trailers | `CLOUD_BACKLOG_PIPELINE.md:51-55`; `cloud-lane-redesign…md:270-273` |
| VM-authored text is untrusted | Asks select an intent from a closed set; no byte reaches a command; no `--execute` | `CLOUD_BACKLOG_PIPELINE.md:1673-1680` (09-10) |
| Same quota pool, no compute charge | Cloud adds zero quota; a cloud fire takes the same router slot and feeds the same 5-hour cutoff. Only dollar path is usage credits (`usage_credits_authorized=false`) | `cloud-lane-redesign…md:182-197,235-237`; `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/cloud-session-cost-exposure.md` (09-23) |
| The lane cannot verify a change to itself | W1 venue producer must be built locally; class `ineligible-offbox-lane`; a VM may not write the admission rule | `CLOUD_BACKLOG_PIPELINE.md:24-27,479-481,1383-1387` |
| Subject-is-this-machine work is a hard floor | ~79% of labelled refusals inherent (live session events, terminal/window server, launchd/kernel, keychain); share rises only if the backlog changes shape | `CLOUD_BACKLOG_PIPELINE.md:896-912` (08-11) |
| The poller cannot be the originator | A goal-armed session may hold no background watcher; poller lives in launchd | `CLOUD_BACKLOG_PIPELINE.md:219-225` |
| A bound must fit the unit | One land costs 700–3,900 s; a 900 s bound cut 36 of 40; hence the dedicated lane tick at 5,400 s | `CLOUD_BACKLOG_PIPELINE.md:1475-1477` |
| Web UI is operator-only | Cloud transcript and permission prompts are answerable only at claude.ai/code; an escalation path, never an automation input | `CLOUD_OBSERVABILITY.md:132-136`; audit `README.md:114-118` |
| VM is Linux, desk is macOS | Several suites are red on trunk inside the VM (BSD-only `stat -f`, `date -r`, `plutil`), so the VM cannot run the full gate faithfully | `docs/research/truememory-adoption-cloud-verdict-2026-09-28.md:66-75` |
| Create path is vendor-internal | `claude --cloud "<prompt>"` bundles (`sources: []`, push 403); `POST /v1/code/sessions` gives a bridge session that runs on this box; the working create mirrors requests recovered from the 2.1.220 binary | `scripts/cloud-create-api.py:11-63` (08-10) |
| Environment is the default one | `init_script: None`, python 3.11 + node 20, `allow_default_hosts: True`; no setup script; environment config recorded as GUI-only | `scripts/cloud-create-api.py:325-344`; `cloud-lane-redesign…md:73` |
| Routines `/fire` route exists, unused | Needs a web-minted per-routine bearer token (operator step); payload arrives labelled untrusted | `CLOUD_OBSERVABILITY.md:623-653` (08-08) |
| No cross-venue in-flight guard | A row being driven by live desk sessions reads `open`; a cloud fire duplicated a wave build on 2026-09-28 | `truememory-adoption-cloud-verdict-2026-09-28.md:45-64` |

## 5 · Open items and pending decisions

| item | state | date |
|---|---|---|
| Decision `7960dccd172f` — keep and fix in place (recommended) vs retire | OPEN, class C, conviction 70, no veto deadline. Named fixes: dead liveness check, landing-arm bounds, empty `paths=` fill; "without widening what the cloud machine can reach" | created 2026-09-23T01:56Z |
| One-time $250 Max cloud credit | Operator-owned; claim by **2026-10-07**, expires 2026-11-04; unknown whether claiming flips the usage-credits toggle | memory note 2026-09-23; `.claude/rules/agent-operating-lessons-situational.md:230` |
| R1 warm reused worktree for cloud lands | NOT done: `scripts/desk-land.sh:147-149` still mints a throwaway `git worktree add` per land | recommended 2026-09-10 |
| R3 add rc 69 to the non-verdict exemption | NOT done: `scripts/cloud-return.sh:800` still `9|75)` | recommended 2026-09-10 |
| Classifier denylist correction (62.5% false-negative) | NOT done: `bin/cc-eligible` has one commit since 09-10 (`04188cf27`, class naming); `ineligible-box` is 156 of 220 routing events since 09-22 | recommended 2026-09-10 |
| `gh` class | `bin/cc-eligible:454` still says "no gh CLI off-box"; the 09-10 memo says vendor docs list `gh` and that line is false | 2026-09-10 |
| `CLOUD_DEPTH` | Still 50 while the brief unshallows; the lockstep constant was never raised | `bin/cc-eligible:759` |
| Wire `cloud-inbox` projection into `cc-cloud classify()` | Recorded as "orthogonal and unfiled" | `CLOUD_OBSERVABILITY.md:2147-2151` (09-02) |
| Two boot contracts in one brief | `scripts/lib/cloud-create.sh:290-292` prepends "commit --allow-empty 'chore: cloud session boot'"; the dispatcher's rail in the same message says "Do NOT make an empty commit" (`bin/cc-dispatch:3207`). One boot commit is on trunk (`25d8a193e`, 2026-09-22) | measured today |
| Stale safety comments | `bin/cc-dispatch:1043` and `:3278` still argue from `CC_DISPATCH_VENUE_ONLY=cloud`, which is off | flagged 2026-09-22 |
| Wave table | `CLOUD_BACKLOG_PIPELINE.md:32-34` leaves W2 and W4 unticked though the body marks both done | flagged 2026-09-22 |
| Blocked rows touching the lane | `f3e662d4e2a8` (S5b ~100 concurrent sessions is a subscription-count question; cloud shares the rate-limit pool); `c5cf7389e102`, `a3c8db13a522` (cloud-parked 10-06 / 10-04, need the desk) | `cc-backlog list` today |

Closed since 09-22 (commit dates): liveness sensor reads LIVE again via a deletion-aware floor (`8a2a9acda`, 09-30); cloud lands were refused 3 of 3 by ship-land's outer-timeout preflight from 09-28 until `3650c703b` (09-30); doc rescue landed 40 doc paths from 39 retired branches (`f79d58a7f`, 09-30); answer rows are now one per cloud session and retract when the session ends (`4595b8a34`, 09-30); create no longer falls back to the public repo slug (`daf52e2f3`, 09-29).

## 6 · Where sources disagree (prefer the newest)

| topic | older | newer | reading |
|---|---|---|---|
| Verdict | RETIRE 70% (09-10 memo L9); packet "OPEN" (`a6-design-record.md:96`, 09-22T06Z) | Superseded 09-23T01:56Z by keep-and-fix, open (live decision store) | keep-and-fix is the standing recommendation; unruled |
| Yield | 12.8% per fire / 15.6% by trailer (09-10); 19.9% (09-16); 20.5% sessions, 116 rows (09-22) | 74% `.returned`, 84% on trunk for the post-09-22 cohort (measured) | different cohorts; old figures are dominated by pre-gate re-fires |
| Cost per landed row | cloud ≈ 0.81× local per fire (08-11); $43.80 vs $31.67 mean (09-10); $32–112 (09-16) | "not computable" (09-22) | no current figure exists |
| Venue filter | cloud-only "do not re-derive" (`CLOUD_BACKLOG_PIPELINE.md:547`, 08-11) | removed 09-07; both venues admitted (plist today) | plan table is stale |
| Lane purpose | "capacity decision" (`CLOUD_BACKLOG_PIPELINE.md:162-164`) | both halves of the valve measured absent (09-10 L15-19); "most productive lane" (09-22) | purpose is unsettled; productivity is not |
| `gh` in VM | absent (`CLOUD_BACKLOG_PIPELINE.md:107-108`, 08-10 VM testimony) | present per vendor docs (09-10 L70) | code still encodes the older claim |
| Quota scarcity | "3.19 account-weeks expired unused; quota is not scarce" (09-16) | last 7 resets 100% used (09-22) | newer says opportunity cost 1:1 |
| Plan status | `CLOUD_BACKLOG_PIPELINE.md` `status: complete` | `BACKLOG_DRAIN_24_7.md` `status: open` supersedes it for operation | read the pipeline plan as architecture reference only |

## 7 · Adversarial pass on this record

- "Standing verdict = RETIRE" was my first reading from the two named docs. Checked against the decision store: refuted (superseded 09-23). The repo HEAD no longer carries the superseding receipt (removed in the 09-26 public-tree scrub), so a repo-only reader will reach the stale answer.
- "74–84% conversion" could be `.returned` paperwork rather than landings (the 09-10 memo's own warning, L138-141). Cross-checked with an independent instrument: trunk trailers give 26 of 31. It holds, but 11 of the 26 are parks or already-cured verdicts and 4 are doc-rescues, so code-bearing delivery is 9 sessions in 15 days (0.6/day).
- "Lane is healthy" overstates: 6 of 15 days had zero fires, and 09-28 → 09-30 every automated land was refused until a fix. Low volume means a multi-day outage shows up as a handful of rows.
- "Supply bounds the lane" rests on one snapshot (1 open row tonight). Adds run 10–81/day (measured), and routing admitted 32 of 220; the classifier's known false-negative rate (09-10) means supply is partly self-imposed. Labelled inference.
- Alternatives the sources considered and ruled out: redesign-split (cost premise refuted); off-box gate on GitHub Actions (tree-sha key structurally dead); headless-browser environment (6 of 6 sampled rows refuted, ≥12 h); cross-repo attach (4 agent-drainable rows for 6–10 h); push-triggered land spawn (arrival 7.3/day vs capacity 24/day); two venue ratchets (one metric with a venue dimension chosen, `CLOUD_BACKLOG_PIPELINE.md:923-973`); provisioning `~/.claude`.

## 8 · Gaps

- No current cost-per-landed-row or per-session token figure; `external_metadata.usage` was not read (would touch the control plane).
- Whether the operator has seen or intends to rule on `7960dccd172f`; whether the $250 credit was claimed.
- Whether the `paths=` empty-fill defect is cured: all 23 returned post-09-22 declarations carry `paths`, but the 8 non-returned ones were not examined individually.
- Whether the reverse-engineered create (`/v1/sessions`, `ccr-byoc-2025-07-29`) and the hidden `claude -p --cloud` send are unchanged in 2.1.284: only inferred from fires succeeding on 10-01 → 10-06; exact date the launcher pin moved to 284 not established (install dir 09-28, `~/.zshrc` mtime 10-01).
- Cloud sessions created outside the declaration store are invisible to every number here.
- `cc-eligible sweep` was not re-run today; the 14.5% admit share comes from routing events, not a census.
- `CLOUD_OBSERVABILITY.md` §5–§13 and `DRAIN_CIRCUIT_2026-09-01.md` body were read by heading and targeted section only; `DRAIN_CIRCUIT` last changed 2026-09-17 and predates both verdict changes.
- GA date (2026-09-23) and unchanged billing come from a memory note, not re-verified against the vendor.

## 9 · Commands behind the measured rows (all read-only)

```
git log --since=2026-09-10 --oneline -- bin/cc-cloud bin/cc-offload docs/plans/CLOUD_BACKLOG_PIPELINE.md   # 4 commits, none functional
git log --since=2026-09-10 --grep='Cloud-session:' --format=%ad --date=short | sort | uniq -c
git log --grep='Cloud-session:' --format=%B | grep -oE 'Cloud-session: *session_[A-Za-z0-9]+' | sort -u | wc -l   # 182
git show --stat 3650c703b f79d58a7f 4595b8a34 8a2a9acda daf52e2f3 6ff54011b 593a21fc3 c2c1660e4
git show caacebf1e:docs/research/decision-consolidation-2026-09-22.md | grep -n -i cloud
plutil -extract ProgramArguments.2 raw {launchd,~/Library/LaunchAgents}/com.claude.dispatcher.plist ; diff -q …
plutil -p ~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist ; launchctl list | grep -E 'dispatcher|autonomy-sweep'
python3 folds over ~/.claude/autonomy/cloud/{*.decl,*.retired,*.returned,*.land-cost,*.land-refused,return.jsonl}
python3 fold over ~/.claude/autonomy/backlog.jsonl (events since 2026-09-22) ; bin/cc-backlog list --all --json
python3 read of ~/.claude/autonomy/decisions/{663522aa67b1,7960dccd172f,ff24ce1f7808}.json
tail ~/.claude/logs/cloud-return-lane.log ; grep 'fire-lane read' … | tail -4
bin/cc-claude-bin ; ~/.claude-284/node_modules/.bin/claude --version
```

Scratch written (only under the allowed directory): `/tmp/cloud-blog-eval/scratch/bl_all.json`, `bl_all.err`.
