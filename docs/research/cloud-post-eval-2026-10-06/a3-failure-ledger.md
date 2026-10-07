# A3 — Failure ledger of the cc-backlog cloud lane (every named failure mode, cause, fix, status today)

Written 2026-10-06 (local; live-store reads taken 2026-10-07T02:07Z). Repo read at
`/Users/chrisren/Development/.worktrees/wt-cc-205652-27362`, HEAD `593a21fc3` (2026-10-06). Read-only.

**Labels.** *measured* = I ran the named command; *documented* = a dated repo doc/commit says so;
*inferred* = my reasoning from those. Paths are relative to the repo unless absolute.

**Deviation from the brief, stated.** The brief's source list is repo docs. To answer "is it still open
today" I also read (never wrote) the lane's live state at `~/.claude/autonomy/cloud/` and
`~/.claude/logs/cloud-return-lane.log` with `jq`/`python3`, and one memory note the rules file points
at. No lane verb (`cc-cloud`, `cc-dispatch`, `cc-offload`, `cc-decide`) was run.

---

## 0 · Headline

- **The lane is alive and converting far better than its history, at a trickle.** Last 15 days
  (declared 2026-09-22 → 10-06): **31 fires over 24 items, 19 returned (61%, Wilson 95% ≈ 44–76%,
  computed by hand), fire→returned p50 0.98 h / p90 6.13 h** — *measured*, python over
  `~/.claude/autonomy/cloud/*.decl` + `return.jsonl`. Lifetime it is 149 of 727 fires landed = 20.5%
  (*documented*, `docs/research/backlog-drain-audit-2026-09-22/a2-cloud-lane.md:53`).
- **Boot, prompt delivery and branch push are not where work is lost today**: 31 of 31 recent fires
  left a pushed ref (*measured*, `.seen` sidecar present). The losses are downstream (land latency →
  conflict/supersede) and upstream (almost nothing is eligible to fire).
- **Most of the September "repair list" was never built.** `git log --since=2026-09-10 --
  scripts/cloud-refusal-route.sh` returns nothing (last touch `7d72371ca`, 2026-09-06);
  `scripts/cloud-return.sh` has one commit since (a 09-30 class-flag migration). The stale-arm
  predicate, the rc-69 latch, the cold per-land worktree and the 5,400 s outer bound are all still in
  the code (§3). The lane works today because volume fell from 30–55 fires/day to ~2/day and the
  box-wide land got ~2.7× faster (`total_s` p50 1,037 → 382 s, `git show 1c5839604`) — *a cure
  verified at a load ~3.5× below the one that broke it* (7.3 arrivals/day on 09-01..10,
  `B3-return-arm-throughput.md:323-326`, against ~2.1/day now).
- **The retire/repair decision is, as far as the repo shows, still open**: packet `663522aa67b1`
  was OPEN on 2026-09-22 (`docs/research/backlog-drain-audit-2026-09-22/a6-design-record.md:96,306`);
  no later ruling is recorded in the repo (*measured*: `grep -rl 663522aa67b1 docs .claude bin scripts`
  → two files, both ≤09-22).

---

## 1 · State today (so every "still open?" below has a baseline)

| fact | value | how (label) |
|---|---|---|
| declarations ever / retired / returned-marker / land-refused artifacts | 757 / 757 / 121 / 98 | *measured* `ls ~/.claude/autonomy/cloud \| sed 's/.*\.//' \| sort \| uniq -c` |
| fires per ISO week | W35 282 · W36 130 · W37 26 · W38 15 · W39 19 · W40 13 · W41 2 (2 days) | *measured* python over `declared_at` |
| last 15 d outcome of 31 fires | 19 returned · 5 conflict · 4 superseded · 2 gone/nothing-to-land · 1 landed by another path | *measured* `.retired verdict=` + ledger `returned` |
| items refired in that window | 6 of 24 (max 3 fires/item) | *measured* |
| ledger outcomes since 09-22T03:00Z | land-refused-cached 588 · pass-scope 506 · land-deferred 159 · land-conflict 120 · waiting 61 · nothing-to-land 55 · returned 18 · abstain 11 · land-refused 10 | *measured* `jq` over `return.jsonl` |
| new land refusals since 09-22 | 9 sessions: rc 6 ×6 (gate red), rc 2 ×3 (outer-timeout preflight) | *measured* `jq … select(.outcome=="land-refused")` |
| refusal routing since 09-22 | routed-vm 5 rows/4 sessions · local-only 4/4 · stale 1/1 | *measured* `jq` over `refusal-route.jsonl` |
| cloud-session trailer commits on trunk, sessions per ISO week | W37 19 · W38 10 · W39 17 · W40 6 (+35 doc-rescue commits on 09-30) · W41 2 | *measured* `git log --grep='^Cloud-session:'` with `%(trailers)` |
| what those commits are (non-rescue, since 09-23) | 7 code/test · 5 park · 5 verdict/close-doc · 1 other doc | *measured* subject regex — approximate |
| lane clocks | fire-lane `LIVE — last fire 9.39 h ago`; return pass rc 0 in 55 s; answer pass `0 active session(s)`; rescue pass 0 branches | *measured* `tail ~/.claude/logs/cloud-return-lane.log` (2026-10-07T02:05Z) |
| eligible supply | 28 of 350 non-done rows eligible, **0 of the 10 open rows** | *documented* 2026-09-22, `a2-cloud-lane.md:184-216` (not re-run) |
| stranded refs | 341 `origin/claude/*` remote-tracking refs locally (may be stale); 346 on 09-22 | *measured* `git for-each-ref`; *documented* `a2-cloud-lane.md:78` |

---

## 2 · The ledger

Class: **P** = platform limitation (VM, clone, credential, boot, prompt delivery, push, reclaim, quota) ·
**O** = our code/config · **M** = platform behaviour that only bites because of how our rails are built.
Status: CURED · WORKED-AROUND (symptom handled, cause stands) · OPEN · LATENT (in code, not firing at today's volume) · UNKNOWN.

### 2a · Create, credential, boot, prompt delivery

| # | date | what failed | root cause | class | fix / workaround | status today | evidence |
|---|---|---|---|---|---|---|---|
| F1 | 08-10 | Session did the whole brief, committed, then `git push` → 403 "not in this session's authorized repository set"; ~13 sessions read as inert | `claude --cloud "<prompt>"` uploads a bundle → `sources=[]` → git proxy injects no credential; installing the GitHub App is necessary but not sufficient | P | Private two-call create (`GET/POST /v1/environment_providers…` then `POST /v1/sessions` with `session_context.sources` + `environment_id`, beta `ccr-byoc-2025-07-29`), acceptance pair enforced, exit 5 otherwise | WORKED-AROUND — depends on an API recovered from the 2.1.220 binary | `scripts/cloud-create-api.py:11-32,56-77,107`; `docs/plans/CLOUD_OBSERVABILITY.md:1673-1690` |
| F2 | 08-10 | API-created session sat `working / disconnected / 0 output tokens` 35+ min; not an error | `bridge:{}` makes `environment_kind: bridge` = a connected client (this box) must drive it | P | same two-call create; never `bridge` | CURED (by construction of the create) | `CLOUD_OBSERVABILITY.md:1760-1772`; `cloud-create-api.py:47-54` |
| F3 | 08-07→08-10 | Every instrument was a ref-watcher, so "did not push" ≡ "did not run"; 222 of 262 sessions filed NOT-STARTED had ended a turn asking a question | no cloud→desk channel except the branch; absence is ambiguous | P | control-plane reader `cloud-inbox.py` (08-27); boot ping as bare ref (`0efcc073`, 09-02); `NOT-STARTED` withdrawn past `life_s` (`7e3124e43`, 09-07); `cc-cloud` reads the inbox `ran=1` record | WORKED-AROUND; 31/31 recent fires show a ref | `CLOUD_OBSERVABILITY.md:1690-1697`; `cloud-boot-contract-restrandings-2026-09-02.md:83-88`; `cloud-dispatch-delivery-2026-09-09.md:21-23`; `bin/cc-cloud:171-172,773-774` |
| F4 | 08-09 | `created-unidentified`: create succeeds, id extraction fails → a live session spending quota nobody can observe or reap | TUI-rendered create output | M | own exit code 11 + printed recovery line | LATENT (API create path returns JSON; residual applies to CLI route) | `CLOUD_OBSERVABILITY.md:1433-1438` |
| F5 | 08-08 | Prompt delivery receipt is unknowable: `claude -p … --cloud <id>` returns `{ok:true}` = *queued*, not read | platform send API has no read cursor | P | `--receipt` refuses (UNKNOWN); the pushed ref is the only proof of receipt | WORKED-AROUND; live send still reads `verdict=cloud-queued enqueued=0` | `CLOUD_OBSERVABILITY.md:949-976`; *measured* last row of `refusal-route.jsonl` (2026-10-01T15:20Z) |
| F6 | 08-08 | A session id is scoped to the account that created it; reads/sends from another account fail | platform account scoping | P | declaration records `account=`; `cc-notify` re-routes to the owning account | WORKED-AROUND | `CLOUD_OBSERVABILITY.md:1123` (heading); *measured* same `refusal-route.jsonl` row: "a session id is scoped to the account that created it" |
| F7 | 09-11→09-16 | Lane returned nothing for 4 days; 719 abstains "keychain item holds no OAuth access token" | `security find-generic-password -s` without `-a` read a second item sharing the service string; error message blamed the credential | O | `6ff54011b` (09-16): narrow by `keychain_account`; suite with a stub that distinguishes `-a` | CURED | `drain-pipeline-productivity-2026-09-16.md:282-327` |
| F8 | 09-29 | A checkout with unreadable origin would have sent a branch-pushing VM at the public repo slug | default `--repo` fell back to a hardcoded public slug | O | `daf52e2f3`: refuse (exit 2) | CURED | `git show daf52e2f3` |
| F9 | 08-11 | "QUOTA CLIFF" abstained with every account at 1–8% of its 5 h window; no dispatcher-driven cloud session had ever been created | account freshness test, not exhaustion | O | plan §A1 | CURED (dispatcher fires daily) | `docs/plans/CLOUD_BACKLOG_PIPELINE.md:554-559,606` |
| F10 | 08-11 | Config flip fired 2 local panes | removing a guard and adding a control land in two readers; a shell program ignores an env var it does not implement | O | interlock: land → converge → prove → remove guard | CURED (procedure) | `CLOUD_BACKLOG_PIPELINE.md:592-601` |

### 2b · The clone and the VM image

| # | date | what failed | root cause | class | fix / workaround | status today | evidence |
|---|---|---|---|---|---|---|---|
| F11 | 08-10→09-03 (≥5 instances) | Landed cures read as "not on trunk"; rows re-derived; a re-derived diff can revert trunk. `is-ancestor` rc 1, `log -S` 1 commit, `git cherry` 0% landed vs 67% unshallowed | checkout arrives **shallow at depth 50**; git answers "cannot see that far" and "no" identically; the horizon moves with each fetch so the false positive self-renews | P | brief FIRST STEP `git fetch --unshallow` (`22b8824c`, 09-01); `cloud-venue-provision.sh` TRUNCATED-HISTORY arm (08-29); `ineligible-deep-history` class | WORKED-AROUND, not cured — rests on the worker obeying prose and on the dispatcher being current (see F33). Recent verdict docs do unshallow (`truememory-adoption-cloud-verdict-2026-09-28.md:13`) | `cloud-shallow-horizon-2026-08-29.md:6-9,18-35,39-50`; `cloud-vm-shallow-clone-blast-radius-2026-08-11.md:53-67`; `CLOUD_OBSERVABILITY.md:2183-2192` ("FIFTH INSTANCE"); `bin/cc-dispatch:3210` |
| F12 | 08-11→08-29 | Every VM-side land exits 9 GATE-KILLED, docs-only included | image has no `bats`/`shellcheck`; our lint treats absence as a non-verdict | M | `cloud-venue-provision.sh` runs `apt-get install` | WORKED-AROUND; sessions that skip it still report "bats is not installed" (09-03, 09-04, 09-07) | `cloud-land-arm-step-2026-08-25.md:552-587`; `cloud-boot-contract-verdict-2026-09-03.md:46`; `cloud-boot-ping-verdict-2026-09-04.md:75`; `cloud-return-row-stratifiers-2026-09-07.md:57` |
| F13 | 08-10→08-29 | `unattended-path-lint --selftest` 11/42 red on Linux → ship-land exit 6 for any diff | the lint judges the executing box's PATH, and the job runs on macOS | O | fixed on trunk `c1904ed8` → 44/44 | CURED | `cloud-land-arm-strand-2026-08-27.md:96-136`; `cloud-land-arm-step-2026-08-25.md:573-576` |
| F14 | 08-29, 08-30, 09-21 | Gate RED (exit 6, "a verdict about your diff") on a correct tree | VM runs as **uid 0**; `chmod 000` negatives invert | M | per-suite repair (directory-as-file construction; explicit root skip) | OPEN as a class: 15 suites on 08-29, **20 today** (*measured* `grep -l 'chmod 000' tests/*.bats \| wc -l`); 3 repaired individually (`b912cd0c3` 09-21 is the latest) | `cloud-land-arm-step-2026-08-25.md:765-793,947-990` |
| F15 | 09-02, 09-28 | Suites red on unmodified trunk inside the VM: `sed -i ''`, `stat -f %m`, `date -r`, `plutil`, iTerm/kitty/pane suites (16 of 83 gate-scoped suites red on pristine, 09-02) | Linux VM vs macOS-authored rails | M | pristine-worktree control per red; no cure | OPEN — 14 cases listed 09-28 | `cloud-boot-contract-restrandings-2026-09-02.md:133-136`; `cloud-boot-contract-second-lane-2026-09-02.md:176-204`; `truememory-adoption-cloud-verdict-2026-09-28.md:69-76` |
| F16 | 09-02 | `cc-dispatch-v2` 17/17 red in any fresh clone, even after `--unshallow` | fixture pins `A2_BASE_SHA=ec92e68c`, an object reachable from no ref | O | none | OPEN — pin unchanged at `tests/cc-dispatch-v2.bats:32` (*measured* grep; red-in-VM is *inferred*, not re-run) | `cloud-boot-contract-restrandings-2026-09-02.md:67-76`; `cloud-boot-ping-verdict-2026-09-04.md:115-118` |
| F17 | 08-10→ | VM has no `~/.claude` layer: `cc-backlog done/block` → `unknown id`, `cc-notify --role desk` → unresolvable (rc 0 until 08-29, rc 3 after); the row stays `open` and is re-fired | the ledger and comms stack live outside the repo the VM receives | M | branch is the only channel: verdict artifact (§14, 08-26), `scripts/cloud-park.sh` → `docs/parks/<id>.md` (08-29), `ineligible-parked` read at claim time (08-30), `cloud-return.sh` step 8 closes/blocks | WORKED-AROUND; structural. 19 of 28 close failures were `unknown id`. 10 of 18 recent cloud commits are parks/verdicts, i.e. the channel carrying "I could not do this row" | `cloud-land-arm-step-2026-08-25.md:471-510,693-725,822-885`; `cloud-already-cured-redispatch-2026-08-26.md:62-104`; `cloud-lane-redesign-2026-09-10.md:253` |
| F18 | 08-16 → 08-22, at least five dispatches (`cloud-venue-project-repo-mismatch-2026-08-16.md:151,179`) | Cross-repo items dispatched into a VM holding only `claude-infrastructure`; unworkable by construction | the create attaches the **firing** repo; one repository per session | P | `ineligible-cross-repo` class refuses them | WORKED-AROUND by refusal: 84 rows refused on 09-22; the 13 cross-repo items ever fired produced 0 commits and 109 reopen events; never a `claude/*` branch on either other remote | `cloud-venue-project-repo-mismatch-2026-08-16.md:1-7,53`; `cloud-venue-foreign-project-2026-08-21.md:7`; `cloud-venue-repo-identity-2026-08-22.md:45`; `cloud-vm-reachability-2026-08-23.md:3-6`; `a2-cloud-lane.md:190`; `cloud-lane-redesign-2026-09-10.md:72,251-253` |
| F19 | 09-02 | VM can create a remote ref and **cannot delete one** (`push --delete` → sideband disconnect on every retry) | git proxy policy | P | desk-side pruner `branch-prune-landed.sh` | OPEN — ~341–346 `claude/*` refs stand | `cloud-boot-contract-restrandings-2026-09-02.md:142-144`; `a2-cloud-lane.md:78` |
| F20 | 08-11 | Push allowed only to the pre-created session branch | platform | P | desk lands every branch (see 2c) | OPEN by design | `cloud-w2-roundtrip-2026-08-11.md:13-14` (first-hand VM testimony; not checked against vendor docs here) |
| F21 | 08-10 | Filesystem not persistent; "anything not pushed is gone"; `df` free space not usable | container reclaimed at session end | P | "push whatever you have before you finish" rail; boot ping | WORKED-AROUND; lifetime 209 of 727 fires never pushed a ref; last 15 d 0 of 31 | `cloud-vm-roundtrip-2026-08-10.md:61-64`; `a2-cloud-lane.md:76`; §1 |
| F22 | 08-10/11 vs 09-10 | `gh` CLI: absent per first-hand VM testimony; "already true" per the 09-10 memo citing vendor docs | sources disagree (§6) | P? | classifier still refuses: "no gh CLI off-box" | UNKNOWN | `cloud-vm-roundtrip-2026-08-10.md:65`; `cloud-w2-roundtrip-2026-08-11.md:21`; `cloud-lane-redesign-2026-09-10.md:70`; `bin/cc-eligible:454` |
| F23 | 09-10 | No browser/dev server in the image | platform tool table | P | `ineligible-visual` (26 rows 09-22) | WORKED-AROUND; low value — seeded sample 6 of 6 rows did not actually need it | `cloud-lane-redesign-2026-09-10.md:73`; `a2-cloud-lane.md:192` |
| F24 | 09-02 | Brief told the VM `git -C /Users/chrisren/…` and `/ship`, `cc-backlog done`, `cc-notify` | brief composed for the desk | O | `0efcc073` cloud-only rails + tail | CURED | `cloud-boot-contract-restrandings-2026-09-02.md:110-121` |

### 2c · Identity, landing, return arm

| # | date | what failed | root cause | class | fix / workaround | status today | evidence |
|---|---|---|---|---|---|---|---|
| F25 | 08-10→09-05 | Push refused after a green gate; then the cure tripped a second hook | VM commits as `Claude <noreply@anthropic.com>` and writes `Co-Authored-By: Claude` / `Claude-Session:` trailers; our pre-push identity gate and `commit-msg` hook refuse both | M | re-author `25aa774af` (08-10); trailer stripper rewritten to cut the lines the hook names, `e49308b92` (09-11) | CURED — all recent artifacts open with "re-authored N commit(s)" (*measured*, 10 newest `.land-refused`). Residual: remote-authored commits land as the operator (131 on 09-10) | `CLOUD_BACKLOG_PIPELINE.md:1248-1290`; `B2-refusal-autopsy.md:235-259`; `cloud-lane-redesign-2026-09-10.md:270-273` |
| F26 | 08-12→08-17 | "could not be re-authored" rc 70 | inherited reaped `TMPDIR` | O | `33cf5df17` | CURED (0 recurrences, 46 successes after) | `B2-refusal-autopsy.md:113` |
| F27 | →08-23 | A bound-killed land left debris that blocked every retry | — | O | `cd5d009b5` | CURED | `B2-refusal-autopsy.md:114` |
| F28 | 08→08-25 | 1,016 `land-refused` events = 80 branch heads asked 12.7× each | verdict re-earned every 300 s | O | head-keyed cache `d3e207b61` | CURED (ratio 1.00); its side effect is F31 | `B2-refusal-autopsy.md:11-14,115` |
| F29 | 08-17→09-06 | "Fires and does not harvest": 309 pushed shas uncollected; lands cut at 720 s; retire pass rc 124; pile cap refused ALL cloud fires for 58.8 h | harvester ran inside the 300 s sweep under a 900 s bound; one land is a 16–65 min unit; a single completed land priced the lane out for 6 h (`fits_bound=false`) | O | lane split `7d72371ca` (09-06/07), 5,400 s bound, retire pass, typed retire verdicts | PARTLY CURED — **price-out still fires**: `land-deferred … land_cost_s 5254 > budget_s 4320 … no tick can ever start this land until the bound changes` at 2026-10-05T02:31Z; 159 rows over 5 sessions since 09-22, 24–35 passes each; one of the five ended `conflict` (*measured*) | `CLOUD_BACKLOG_PIPELINE.md:1455-1503`; `a2-cloud-lane.md:133-139`; live `return.jsonl` |
| F30 | 09-08→09-10 | 25 of 25 land invocations SIGKILLed by the lane's own bound; 0 lands for 3 days with 13 clean branches waiting | fresh `git worktree add` per attempt (arms p50 870 s vs 340 s warm; 37.5% ≥3,500 s); unlocked gate round invalidated ~96% of the time by trunk (median gap 431 s) → exit 42 → 143 | O | proposed R1–R6; **none of R1/R2/R4/R5 is in the code** (`scripts/desk-land.sh:149` still `worktree add`; `scripts/cloud-return-lane.sh:68` bound 5400; no `GATE_ROUNDS` setting). Indirect relief: ratchet memo (`606d26bfb`, arms p50 365 → 220 s) and LAND_SPEED (box-wide `total_s` p50 1,037 → 382 s, re-round exhaustion 28 → 0; `1c5839604`) | MITIGATED, not cured; unverified at the load that caused it | `B3-return-arm-throughput.md:8-14,118-135,198-212,291-300`; `git show 6bb41fc64 1c5839604` |
| F31 | 09-09 | A clean branch permanently latched out after one `git ls-remote` blip (rc 69 SENSOR FAILED) | refusal cache exempts only 9 and 75; a retired VM never moves the head | O | proposed one-line fix | LATENT — `scripts/cloud-return.sh:799-800` still `9\|75)`; no rc-69 event since 09-22 (cached `prior_rc` only 2 and 6, *measured*) | `B2-refusal-autopsy.md:278-291`; `B3-return-arm-throughput.md:275-287` |
| F32 | 08→09-06 | 630 of 675 refusal routings said "already landed, nothing routed"; ≥358 wrong; only 4 refusals reached a VM in a month | `stale_resolved()` ARM 2 tests file **presence** on trunk, not content | O | proposed one predicate | LATENT — `scripts/cloud-refusal-route.sh:400` still `ls-tree`; since 09-22 only 1 of 10 routings was `stale` and 4 sessions were routed to their VM | `B2-refusal-autopsy.md:128-218` |
| F33 | 08-25→09-09 | 273 of 313 "routed-originator" rows were undelivered (`no-such-target`, pane 5 gone since August); one refusal re-sent 97× | ledger row written unconditionally; dedupe skipped on failure | O | proposed ~2 lines + a fallback target; not built | LATENT — `cloud-refusal-route.sh:549-554` is byte-for-byte what B2 quoted (file untouched since 09-06): only rc 0/3 enter the dedupe store, the ledger row is unconditional. 4 `local-only` routings since 09-22; their delivery is not recorded in what I read | `B2-refusal-autopsy.md:304-324`; `CLOUD_BACKLOG_PIPELINE.md:1471-1490` (§A9.2 M7) |
| F34 | 08-09→09-22 | `paths=` empty at declare → `LANDED` unreachable for 598 of 727 declarations; 13 of 19 sessions skipped on 09-08..10 | the dispatcher cannot know what a VM will touch; no channel for the VM to declare it | M | `fill-paths` derives paths pre-land (`paths_src=caller-derived-pre-land`) | MOSTLY CURED — 23 of 31 recent declarations carry paths (*measured*); `f79d58a7f` re-measured it as "no longer the mechanism" | `CLOUD_OBSERVABILITY.md:1446-1462`; `a2-cloud-lane.md:94-109`; `cloud-lane-redesign-2026-09-10.md:127-129` |
| F35 | →08-24 | 21 of 29 `lane:"cloud"` closures cite a path set their session never produced; 13 rows closed on a non-existent deliverable | stale shell global `PENDING_PATHS` (strong hypothesis) | O | `fill-paths --print/--set` split, 08-25 | CURED going forward; the 13 false closures stood on 09-16 — UNKNOWN today | `drain-pipeline-productivity-2026-09-16.md:132-143` |
| F36 | 08-11→08-17 | 105 close failures `cc-backlog done: unknown id` on ids that exist; 34 with `getcwd` errors | lander ran from a deleted worktree | O | — | CURED (zero since 08-17) | `a2-cloud-lane.md:79` |
| F37 | 09-28→09-30 | Every automated cloud land exited 2 `reason=outer-timeout` (3 of 3) | new ship-land preflight (`ba8e5c24a`) refuses a land with `timeout` in its ancestry; the lane runs under exactly such a bound | O | `3650c703b`: `SHIP_ALLOW_OUTER_TIMEOUT=1` on the return child | CURED; the 3 sessions ended `superseded` (*measured*), their docs rescued | `git show 3650c703b`; §1 |
| F38 | 09-10→09-30 | Retiring a branch frees the row and abandons its content: 155 files added by 88 refs existed nowhere on trunk | retirement is a custody verdict, not a content verdict | O | `--rescue-docs` pass (`f79d58a7f`): 35 one-file rescues landed 09-30 | PARTLY CURED — only files ADDED under `docs/`; code on retired branches stays stranded | `a2-cloud-lane.md:78,88`; `docs/lessons/retiring-a-population-is-not-recovering-its-work.md:5`; `git show f79d58a7f` |
| F39 | lifetime; 09-22→10-06 | Branch conflicts or its item closes before the desk lands it: 296 of 567 non-delivering sessions (52%); 93.4% were landable at push, 90.0% at +1 h, 28.1% at +7 d; observed median lag 207 h | land latency vs trunk churn (80 commits/day), multiplied by sibling fires | M | merge-tree precheck `7d72371ca` prices a conflict in ~1 s; no VM-side rebase-before-final-push rail exists in the brief (*measured*: `grep -i rebase bin/cc-dispatch bin/cc-offload scripts/lib/cloud-create.sh` → two comments about local waves, no brief text) | OPEN at lower volume: 5 conflict + 4 superseded of 31 (29%) in the last 15 d | `B1-stranded-branches.md:14-18,136-144`; `drain-pipeline-productivity-2026-09-16.md:98-102`; §1 |
| F40 | 09-22→10-01 | Gate red found only at the desk: rc 6 on 6 sessions — `dead-assertion` ×4, `TSV field-collapse` ×1, a failing suite ×1 | the VM does not run the land gate's ratchet lints before pushing | M | W3 refusal loop routes the verdict to the VM, which re-pushes | WORKED-AROUND and working: 4 sessions routed, all three 10-01 refusals later `returned`; costs one extra round trip | *measured* `.land-refused` bodies + `refusal-route.jsonl`; design `cloud-w3-refusal-loop-2026-08-11.md:9-17` |

### 2d · Dispatch, re-fire, observability of the lane itself

| # | date | what failed | root cause | class | fix / workaround | status today | evidence |
|---|---|---|---|---|---|---|---|
| F41 | 08-11→09-04 | Re-fire loop: 545 of 727 declarations are re-fires (worst item ×38); 211 of 688 fired *after* their own item had landed | `open` is the fire predicate; land→`done` lag median 2.33 d, p90 12.19 d; VM cannot close (F17) | O (M via F17) | already-declared gate + pile cap `124c4da06` (09-04): post-land re-dispatch 210 → 1 | CURED for the loop; residual 6 of 24 items refired 2–3× in 15 d (release-after-retire is by design) | `a2-cloud-lane.md:30-34,75`; `cloud-dispatch-delivery-2026-09-09.md:27-65` |
| F42 | 08-25→09-04 | One contract implemented 9 times on 9 stranded branches, 0 landed; another row dispatched 11 times | F29 + F41 + F17 together | O | `0efcc073`; park channel | CURED | `cloud-boot-contract-restrandings-2026-09-02.md:24-48`; `cloud-land-arm-step-2026-08-25.md:797-812` |
| F43 | 09-02, 09-03, 09-09 | Cure landed, dispatcher still composed pre-cure briefs ≥13 h 54 m later | landed ≠ live: the actuator converges on no schedule tied to the landing | O | `DISPATCHER VINTAGE` rail `f9cbe177` | CURED/monitored — vintage EQUAL in 09-04, 09-07, 09-25, 09-28 sessions | `cloud-boot-contract-second-lane-2026-09-02.md:56-70`; `cloud-boot-contract-verdict-2026-09-03.md:60-76`; `docs/parks/e8010ba4b98a.md:15` |
| F44 | 08-29→09-02 | Park landed and the wave fired anyway (7 h 11 m later) | the park's only reader was the dark return arm | O | `ineligible-parked` at claim time | CURED | `cloud-land-arm-step-2026-08-25.md:804-841` |
| F45 | 08-25→09-01 | Unmanaged fires (no `notify_back`/`custody`) produced branches the sweep was not allowed to land | dispatch policy | O | fires declare custody | CURED — newest declaration carries `custody=` (*measured*) | `cloud-boot-contract-restrand-2026-09-01.md:93-103` |
| F46 | 09-16→09-30 | Lane liveness sensor permanently VOID (exit 3) | pinned ref floor of 426; the sibling pruner deleted refs | O | prune journal `0b24210f8` + deletion-aware floor `8a2a9acda` | CURED — reads LIVE (*measured*) | `a2-cloud-lane.md:141-180` |
| F47 | 09-08→09-16 | Detectors ran 0 times/day; lane death found by a human | 900 s arm inside a 400 s self-bounded tick | O | `d8b13504e` (09-16) reorders the arms (commit subject only; not re-verified) | CURED per commit; UNKNOWN in effect | `drain-pipeline-productivity-2026-09-16.md:197-208` |
| F48 | 09-28 | VM built 5 items a desk program was landing in parallel; 73 trunk commits later the branch was reset to a verdict doc | dispatcher sees `open`, not "a live desk session owns this row" | O | none found (`grep` for an owner guard in `bin/cc-dispatch` → nothing; *inferred* open) | OPEN | `truememory-adoption-cloud-verdict-2026-09-28.md:40-64` |
| F49 | September | Cloud sessions stalled on a permission grant or a question answerable only in the web UI: 65 block events naming 8 sessions | human-in-the-loop inside an unattended lane | P | `cloud-inbox.py` + answer pass (`cloud-answer.py`, one row per session `4595b8a34`) files a needs-human row | OPEN (surfaced, not removed); 0 active sessions at 10-07T01:51Z | `backlog-drain-audit-2026-09-22/README.md:113-118` |
| F50 | 09-08→ | `abstain why:"state UNKNOWN"` ×40 in 3 days | transient control-plane read failures under load | P | abstain and retry | OPEN, small: 11 abstains over 5 sessions since 09-22 (*measured*) | `B3-return-arm-throughput.md:225-229` |
| F51 | 09-10 | Classifier refuses on the word "box": 62.5% false-negative over its refusals (35 of 56, n=60 flow sample); 3 of 7 admits were false | spelling denylist | O | none recorded | OPEN — `ineligible-box` still 146 rows on 09-22 | `A2-reach-flow.md:12`; `A1-reach-stratum.md` summary; `a2-cloud-lane.md:189` |
| F52 | 09-10→09-22 | 133 (09-10) / 119 (09-22) open cloud custody debts with no reader | custody opened against the dispatcher's cwd | O | `512679a5e` (09-28) "only a terminal HANDOFF-PING discharges" | UNKNOWN | `cloud-lane-redesign-2026-09-10.md:292`; `backlog-drain-audit-2026-09-22/a7-worker-path.md:96,326` |
| F53 | 09-10 | Instruments lie: `returned` rows are paperwork (35 rows vs 5 real lands); a pass killed inside the lander writes no row | ledger design | O | none recorded | UNKNOWN | `B3-return-arm-throughput.md:28-38` |
| F54 | standing | Cloud adds no quota: sessions draw the same Max pool | vendor-stated; reproduced 14 of 55 vs 0 of 65 hours, p = 6.5e-06 | P | none possible on our side | OPEN (structural). Adjacent, unverified by me: a one-time $250 cloud-only credit, claim by 2026-10-07 | `cloud-lane-redesign-2026-09-10.md:180-197`; `.claude/rules/agent-operating-lessons-situational.md:230`; `~/.claude/projects/-Users-chrisren-Development--worktrees-wt-5fb957ffb085/memory/cloud-session-cost-exposure.md` (2026-09-23) |

---

## 3 · Which failures are platform limitations (the brief's seven axes + two)

| axis | platform facts the sources establish | failures | what we did | cured? |
|---|---|---|---|---|
| **VM** | Firecracker Linux, hostname `vm`, uid 0, `/home/user/<repo>`, no `bats`/`shellcheck`, no operator `~/.claude`, proxied egress (`cloud-vm-roundtrip-2026-08-10.md:9,27-32,65-74`) | F12, F14, F15, F17, F23 | apt provisioning script; per-suite uid repairs; branch-as-channel | no — worked around; F14/F15 open |
| **clone** | one repository, shallow at depth 50 | F11, F18 | `--unshallow` rail; refuse cross-repo | no — both worked around |
| **credential** | git proxy injects a credential only for the session's `sources`; session ids are account-scoped; create uses the account's OAuth token | F1, F6 (F7 was ours) | private two-call create | worked around |
| **boot** | a `bridge` session never runs; a cloud session that ran and pushed nothing looks like one that never booted | F2, F3 | create acceptance pair; boot ping; control-plane reader | worked around; not losing work now (31/31) |
| **prompt delivery** | send returns *queued*; no read receipt | F5 | refuse receipts; the first push is the proof | worked around |
| **branch push** | only to the session branch; can create a ref, cannot delete one; commits authored as `Claude <noreply@anthropic.com>` with AI trailers | F19, F20, F25 | desk lands, re-authors, prunes | F25 cured; F19/F20 open |
| **idle reclaim / end of session** | container reclaimed at session end; unpushed work is lost; a session can end a turn waiting on a question | F21, F49 | push-early rail; answer pass | worked around. **No source measures an idle timeout** (gap) |
| **quota** | same pool as local | F54 | — | open |
| **control plane** | readable from the desk; transient failures under load | F50 | abstain | open, small |

Everything else in §2 is ours. By count: 15 P (one of them, F22, uncertain), 9 M, 30 O of 54 rows
(*measured*: `awk` tally of the class column of this file).

---

## 4 · What recurs, and what was worked around rather than cured

**Recurring (same generator, new instance):**
- Shallow horizon — ≥5 dated instances 08-11 → 09-03, each at a different boundary commit (F11).
- "Row re-fired because the VM could not move its state" — verdict artifact (08-26) → park (08-29) →
  park-reader (08-30) → already-declared gate (09-04); four cures for one generator (F17/F41/F42/F44).
- "Bound smaller than the unit" — 240 → 900 s (08-11), lane split to 5,400 s (09-06), SIGKILL at
  5,400 s (09-08), price-out at 5,254 s vs a 4,320 s budget (10-05) (F29/F30). Still live.
- Venue-false gate reds — unattended-path (F13), missing tools (F12), uid 0 (F14, three instances),
  BSD-only calls (F15, 09-02 and 09-28), unreachable fixture object (F16).
- Detector dark before the thing it watches — 08-17 step read as a probe artifact; 09-08 starved
  arms (F47); 09-16 liveness void (F46).
- A cure that breaks the lane — the head cache (F28) created the rc-69 latch (F31); the outer-timeout
  preflight (F37) refused every cloud land for two days.

**Worked around, cause standing:** F1 (private API), F3/F5 (no receipt), F11 (prose rail), F12
(provision step), F17 (branch as channel), F18 (refusal), F21 (push-early), F39/F40 (desk-side land +
refusal loop), F49 (surfaced to a human).

**Named as fixable on 09-10 and not built** (*measured* against the code): warm land worktree (R1),
`SHIP_LAND_GATE_ROUNDS=0` on lane lands (R2), rc 69 exemption (R3), no outer bound on the land (R4 —
the opposite was chosen, an explicit override), classify-before-land (R5), stale ARM 2 content test,
unconditional `routed-originator` ledger row, VM-side `fetch && rebase` before the final push
(`cloud-lane-redesign-2026-09-10.md:156-171` vs `scripts/desk-land.sh:149`, `scripts/cloud-return.sh:799-800`,
`scripts/cloud-refusal-route.sh:400,554`, `scripts/cloud-return-lane.sh:68,200`). Built: trailer
stripper (`e49308b92`), ratchet memo, doc rescue.

---

## 5 · Still-open platform-side pain, ranked by landed throughput it costs

Ranking is *inferred*; each row carries its measured or documented size. Two different quantities are
in play and are kept apart: **supply** (rows the lane may fire) and **conversion** (fires that land).
Today supply binds: ~2.1 fires/day at 61% conversion ≈ 1.3 returned sessions/day.

| rank | pain point (class) | lifetime cost | cost in the last 15 days | why this rank |
|---|---|---|---|---|
| 1 | **The VM cannot land or rebase onto trunk; every push waits for a desk-side land** (P+M: F20, F39, with F29/F30 as our amplifier) | 296 of 567 non-delivering sessions died superseded/conflict; 90% were landable at +1 h (*documented*) | 9 of 31 fires (29%) ended conflict/superseded; 3 of those 9 were our preflight bug, ≥2 were sibling refires (*measured*) | Largest conversion loss in every window measured; the only one that scales with supply |
| 2 | **One repository per session** (P: F18) | 13 items, 0 commits, 109 reopen events; 106 of 133 stranded sessions in one cohort targeted an unreachable repo (`docs/lessons/a-count-in-the-title-is-a-population-and-a-population-disposes-i.md:5`) | 84 of 350 non-done rows refused (09-22); in the 09-10 agent-drainable stock, repo attach + a `gh` token lifts reach 7 → 13 of 36 (`A1-reach-stratum.md` summary) | Largest platform-side supply unlock on record; discounted because most cross-repo rows are operator errands (4 drainable, `cloud-lane-redesign-2026-09-10.md:72`) |
| 3 | **No channel from VM to the ledger but a landed file** (M: F17) | 68% of docs landings were self-reports about mis-dispatch (`cloud-lane-redesign-2026-09-10.md:256-258`) | 10 of 18 non-rescue cloud commits are parks/verdict docs (*measured*, approximate regex) | Roughly half of what lands is "this row was not cloud work"; each costs a full session and a full desk land |
| 4 | **Image/OS mismatch with the land gate: no bats/shellcheck, uid 0, GNU userland** (M: F12, F14, F15, F40) | six dispatches of one row stranded on it (`cloud-land-arm-step-2026-08-25.md:552`) | 6 of 31 fires took a gate-red refusal; 3 recovered through the loop | Costs a round trip on ~1 in 5 fires rather than the row |
| 5 | **Same quota pool** (P: F54) | adds zero capacity; a cloud fire takes the same router slot | unchanged | No landed-row loss by itself; it caps what any other improvement can buy when quota binds |
| 6 | **Sessions that stop to ask** (P: F49) | 222 of 262 "NOT-STARTED" had ended a turn on a question (08-27); 65 block events / 8 sessions in September | not measured after 09-22 | Each is a paid session that waits on a human |
| 7 | **Shallow clone** (P: F11) | ≥5 mis-diagnoses; 9-dispatch and 11-dispatch loops traced partly to it | 3 rows refused `deep-history` (09-22); one fetch per session | High historical cost, low now, while the prose rail holds |
| 8 | **Private create path** (P: F1) | 13–15 sessions lost before the workaround | 0 losses; lane fired 2026-10-06T16:42Z | Availability risk, not a current cost; not re-verified against the CLI now installed |
| 9 | **Cannot delete refs; unpushed work is reclaimed** (P: F19, F21) | 209 of 727 fires never pushed | 0 of 31 | Hygiene today |

Alternatives considered for rank 1: ranking the shallow clone first (it caused the most *recorded
incidents*) — rejected because incidents are not landed rows and its current cost is one fetch;
ranking quota first (it defeats the lane's stated purpose) — rejected for this question because it
removes no landed row at today's volume, though it is the constraint on scaling (rank 5 says so).

---

## 6 · Where sources disagree (newest wins unless noted)

| topic | older | newer | reading |
|---|---|---|---|
| Is the lane dead? | "both lanes are stopped" (`drain-pipeline-productivity-2026-09-16.md:19`) | "alive, most productive of the three" (`backlog-drain-audit-2026-09-22/README.md:43`; `a8-adversarial.md:48`) | alive; confirmed 10-06 (§1) |
| Yield | 12.8% (88/688) | 15.6% (108/692), 19.9% (146/708), 20.5% (149/727); per item 48–52% | denominators differ; last 15 d is 61% per fire |
| Cost per landed row | $36–44 (`cloud-lane-redesign-2026-09-10.md:205-208`) | $32–112 (`drain-pipeline-productivity-2026-09-16.md:216-226`) | both divide by lifetime conversion; neither describes the last 15 d |
| `gh` in the VM | absent (first-hand, 08-10/11) | present per vendor docs (09-10 memo) | unresolved — the memo's receipt `A3-config-pricing.md` is **not in the repo** (*measured* `ls`) |
| Was the 08-17 step real? | probe artifact (`a42f107a` message) | real and intermittent (`cloud-land-arm-step-2026-08-25.md:21-30`) | real |
| rc 70 after the TMPDIR cure | "did not close it" (`B1-stranded-branches.md:172-175`) | rc 70 was a collapse bucket until 09-04; TMPDIR has 0 recurrences (`B2-refusal-autopsy.md:47-50,113`) | B2 |
| Is the `paths=`-empty skip live? | dominant abstention (09-10) | "no longer the mechanism" (`f79d58a7f`, 09-30) | cured |
| `CLOUD_BACKLOG_PIPELINE.md` `status: complete` | frontmatter | refuted by the open packet (`a6-design-record.md:96`) | plan is not complete |

---

## 7 · Adversarial pass (what would make this ledger wrong)

- **"61% proves the lane is fixed."** n = 31, CI 44–76%, at ~2 fires/day. The two mechanisms that
  zeroed it on 09-08..10 are unbuilt and one fired on 10-05 (F29). Raising supply without R1–R4
  reproduces August's strand — the 09-10 memo's own warning (`cloud-lane-redesign-2026-09-10.md:77-79`).
- **"31/31 pushed proves boot and delivery are solid."** The boot ping makes a ref appear before any
  work, so a ref no longer proves work: 2 of 31 were `nothing-to-land`. And a create that fails
  writes no declaration, so failed creates are invisible to this store (`a2-cloud-lane.md:386-392`).
- **"LATENT means harmless."** F31 and F32 are quiet because refusals are ~9 sessions per 15 days;
  both scale with refusal volume.
- **"Platform vs ours is clean."** It is not for the M rows: the identity wall, the uid-0 reds and the
  missing tools are platform facts that hurt only because the land gate is macOS-bound and strict.
- **My commit classification** (park/verdict vs code) is a subject regex; the 10-of-18 figure is
  approximate.
- **Local `origin/claude/*` ref count** (341) is the worktree's last fetch, not a fresh `ls-remote`.

---

## 8 · Gaps

1. No source measures an idle-reclaim timeout, a session lifetime cap, or what happens to a VM that
   pushes a ref and then freezes (226 STALLED sessions "not post-land waste", named unmeasured at
   `cloud-dispatch-delivery-2026-09-09.md:80-82`).
2. Whether packet `663522aa67b1` has been ruled since 09-22 — not determinable from the repo; I did
   not run `cc-decide`.
3. Whether the private create path still matches the CLI now installed (v2.1.284 per the request) —
   the lane fired today, which shows the path works from whatever binary the dispatcher uses; I did
   not inspect the binary.
4. Create failures and out-of-band sessions leave no local record.
5. Status of F35 (13 false closures), F47 (detector reorder in effect), F52 (custody debts), F53
   (ledger undercount) after 09-22.
6. `gh` availability in the VM (F22) — needs one in-VM `command -v gh`, which I may not run.
7. Current eligible-queue size — last measured 2026-09-22; `cc-eligible sweep` not re-run.
8. Token/quota spend of the last 15 days' fires — no per-session usage record reaches this box
   (`a2-cloud-lane.md:401-404`).
9. `CLOUD_OBSERVABILITY.md` §6.4 (entitlement/attach gating, lines 478-543) was read at heading level only.
