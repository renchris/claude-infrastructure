<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/d8422690-9b86-47a2-8462-8a780e010603.jsonl
 turns=100 assistant_texts=10 last_stop=end_turn mail_injections=[] -->

Predictions held — saturation reached. The two untouched audit docs (W0-W3, SESSION_AUTONOMY) confirm the same classes with more instances **plus the unifying design law** ("Fail-loud/fail-abstain, never fail-silent-open"; "Absence is SILENT where STALE is LOUD"; "a silently-crashed daemon is indistinguishable from a quiet [healthy] one") — no new mechanism class. DEPLOY-NOW.sh does `git merge --ff-only` with **no `ln -s`** → confirms the new-file-never-linked gap is real and unremediated; deploy-parity-assert.sh is explicitly READ-ONLY detection covering only `~/bin` copy-tools, not the `~/.claude/**` new-file case. Next call would surface another instance of an identified class → stopping.

---

# Silent-Failure Incident Corpus — claude-infrastructure

**Method:** history-backward over 47 memory distillations + 7 research docs + git log (full history) + live `backlog.jsonl` (1,262 events folded) + on-disk verification. Empirical (measured/disk-truth) vs theoretical (inferred) marked per claim. Every row cited to a memory file, commit SHA, backlog id, or `doc:line`.

**The through-line (operator's named axis):** *every* silent failure here is **one shape** — a **proxy signal stays healthy-looking while the real state has failed**. The failed state is indistinguishable from the healthy state *by the signal being watched*. Fix family is therefore always the same three moves: (1) read the **durable effect-product** not the proxy, (2) **fail-loud-on-inert** (alarm when a mechanism abstains ~100%), (3) render it on a **human-visible surface**.

## (a) Incident table

Class codes: **P** verify-by-proxy · **D** deploy-lag/symlink · **S** stranded-output · **F** fail-open/blind-check · **C** config/mechanism-drift (built≠live≠firing) · **W** wrong-causal-attribution · **X** crash/self-erasing-evidence

| Date | What failed silently | Cls | Detection-lag | Surfaced by | Cost | Citation |
|---|---|---|---|---|---|---|
| ~Jul 11→Jul 23 | Sessions "crash to shell"; chased OOM/bloat theory, actual = **CC 2.1.207 version regression** (4.76% mid-Bash) | X | **~11 days** (2 wrong theories) | 8,637-transcript version-normalized scan | lost 65MB/16,963-rec sessions; ~11d misattribution | `session-crash-diagnosis-2026-07-22.md`; `session-crash-per-session-bloat.md` |
| Jul 15→20 | Cross-session mail **78% unacked** (1,401/1,788 lines); 39 dead boxes; **0 watchers / 16 live** | S | **≥5 days**, some **permanent** | forensic mailbox survey | pages/decisions never reach humans | `cross-session-mail-2026-07-20.md:47-59` |
| Jul 20 | Desk self-recycle **armed under wrong config** (.claude-tertiary vs live .claude-quaternary) → **abstained 1,309×, fired 0** | C | **days** | abstain-alarm (built *after*) | no auto-recycle for days; memory claimed it worked | `feature-durability-mechanism-not-memory.md:14` |
| Jul 23 | 16-agent wave: named-subagent reports **stranded in transcripts**; `idle_notification ≠ delivery` | S | until noticed | disk-harvest by `agentName` | synthesis stalls indefinitely | `wave-report-harvest-from-disk.md:11` |
| Jul 17→19 | `claude-accounts` **stale in ~/bin 2 days**; handoff-fire read `stale_quota` field deployed binary never emitted → **"weekly n/a" forever** | D | 2 days | deploy-parity-assert (built *after*) | every quota consumer ran old code | `scripts/deploy-parity-assert.sh:5-12`; fix `e7bf7e6` |
| Jul 20→now | Deploy **new-file-never-linked**: lr-reset-poller resolves helper next to itself → `~/.claude` copy, **unlinked** → would **silently stop resuming limit-parked sessions** | D | caught at land | running the **LIVE** symlinked path pre-land | near-silent fail-closed of autonomy spine | `deploy-lag-checkout-behind-origin.md:27-49` |
| Jul 20 | Shared checkout **6 commits/18h behind origin**; firefought zombie STALL?/DEAD pages + reaper Δ1 **already fixed-not-deployed**; re-dispatched a worker for done work | D | ~18h | printed `rev-list HEAD..origin` | ~½ session wasted on moot symptoms | `deploy-lag-checkout-behind-origin.md:16-20` |
| Jul 19 | cc-dispatch **fixture-shape mismatch** (argv-array vs flat-string): **7/7 live spawns died, green through 3 landed versions + 2 land-cycles** | F | **~5 land-cycles** | live spawn failure | desk-24x7 activation stalled | `fixture-shape-parity-with-real-producer.md:10-14` |
| Jul 19 | cc-dispatch **false quota-cliff** (whole backlog > 8 slots) abstained every tick; **28 items stranded** while next4 at 0%; handed down as "correct wait state" | F+W | hours | disk-probe rank + wave-plan | hours stranded queue | `dispatch-false-cliff-wave-sizing.md`; fix `bef587a` |
| Jul 18 | Team `44f5331d`: **4 "Teammate failed"** but **all had complete reports on disk** | S+P | until disk-checked | stat brief-declared deliverable paths | risk of re-running 200k-tok finished teammates | `team-recovery-disk-truth-over-notifications.md:11-16`; fix `adf51d4` |
| Jul 20 | handoff-fire **`/goal`-prefix** brief (6,861>4,000 chars) **rejected**, but "engagement confirmed (birth)" printed | P+F | ~1,800s (supervisor page) | worker STALL?/0% ctx | idle worker until nudge | `handoff-fire-goal-prefix-trap.md`; backlog `ff2d6609a33e` (done) |
| (structural) | engagement-verify checked **transcript BIRTH not first-assistant-turn** → "engaged" on non-engaged sessions | P | — | root-caused post-incident | the enabler of the two rows above | fix `ef11307` |
| Jul 17 | Cold `--worktree` fire **auto-submit race** → session never engaged; **"→ fired (cold)" looked successful** | P | until 0-commits noticed | grep brief text across transcripts | stalled build until warm re-fire | `cold-worktree-fire-autosubmit-race.md:13` |
| Jul 19 | reaper-blindness `2be82e97`: panes started **before** `session-register.sh` wiring never registered; write-once never backfills | C+S | days | cc-sessions Δ vs live | registry blind; **first root-cause (it2-gate) was WRONG**, burned a dispatch | `reaper-blindness-it2-gate-rootcause.md` (empirical: theory self-refuted); fix `ad37447` |
| Jul 16 | **"next2/next3 rate-limited"** false claim from bare `429` grep + poll-throttle **mislabeled** as account-limit (all accts 0-24%) | W | same session | real usage-% read | wrong routing decision | `desk-read-transcript-before-asserting-why.md:20`; fix `013502f` |
| Jul 16 | **"marquee resumed on its own"** from `index.html` appearing; actual = fable model-pin **silently ignored** (ran Opus), hung 35min, operator manually resumed | W+C | 35 min | operator narration | 35min dead spawn + wrong causal claim | `desk-read-transcript-before-asserting-why.md:24` |
| Jul 16 | Monitor **false RECYCLE_NOW ×2** (`BASE=$(git rev-parse HEAD)` recompute missed b3b0e82/24b14ed) | P | per-window | printed BASE changed | near-interrupt of working lead mid-flight | `desk-monitor-fixed-head-ref.md:14` |
| Jul 17 | **False MERGE** from `--short` SHA abbreviation drift (`eae0b86`→`eae0b861`, same commit) | P | per-wake | `rev-parse\|grep '^oldref'` | near-false "pass-1 landed!" | `desk-monitor-fixed-head-ref.md:33-42` |
| Jul 16 | cc-notify **misrouted 3 nudges** to hung teammate (mapped pane by **name/age/cwd** not sessionId) | P | 33 min | `--list --json` sessionId | successor unreached 33min; decision un-relayed 30min | `cc-notify-session-pane-mapping.md:18-24` |
| Jul 19 | Desk **reopened already-landed A2** (`41f2146b`, since landed `2c2f3ff`) on a stale early-turn check | P | intra-turn | fresh `git ls-tree origin/main` | redundant redo + transient misroute to next3 | `desk-verify-fresh-before-mutating-backlog.md:10` |
| Jul 15 | **stdin-eater**: `python3 - <<PY … stdin.read()` → guard reads empty, `except:exit 0` **passes every call** | F | caught at build | criteria-first RED-proof (LR-c) | pre-land (blind guard) | `blind-check-generators-stdin-and-sid-keys.md:13` |
| Jul 15 | **sid-keyed idempotency marker** → session could never re-park on its **next** 5h limit | F | caught at build | RED-proof (LR-i) | pre-land (fatal for multi-day autonomy) | `blind-check-generators-stdin-and-sid-keys.md:21` |
| Jul 14 (W4) | Driver teammate pane **died SILENTLY mid-queue** (GO-deaf #3) | S+X | until noticed | became `D8` detector after | strand of in-flight work | `W0-W3_INTERVENTION_AUDIT.md:207-212` |
| (W-series) | Stall detector **fail-silent past 6h**; a STALE row **VANISHED** ("absence silent where stale loud") | F+C | >6h overnight | — | stall invisible overnight | `W0-W3_INTERVENTION_AUDIT.md:320-334`; fix `93720eb` |
| (accounts, ×5) | stale/elapsed quota **rendered as live** (`1429f77`,`4b4019e`); missing reset **read as imminent** not far (`160b8f3`); per-account probe fail **blanked whole fleet** (`05e2bb3`); routing **silently dropped** (`2252a6d`) | P/F | varies | adversarial review + tests | wrong routing on stale/blanked data | git `fix(accounts)` ×12 |
| (open) | `completion-assert.sh:42` emits **MALFORMED IDL** (raw `%s` of unescaped reason) — the fail-loud **ledger itself** corrupted | F | — | filed | corrupts the alarm store | backlog `666c6a64c45e` (done) |
| (open) | `ship-land` esc_scan **fail-opens on grep error** (pattern without `--` → leading-dash SID) | F | — | filed | escalation-scan silently skipped | backlog `1b784d80d4d5` (**OPEN**) |

## (b) Class table

| Class | Incident count | Structural fix? (cite) | Recurrence after "fix" | Best <1-min detection primitive |
|---|---|---|---|---|
| **P — verify-by-proxy** | ~10 | Partial: engagement=real-turn (`ef11307`); cc-reconcile (`ad37447`); sessionId-only mapping (memory). **No general primitive.** | **HIGH — class keeps regenerating in new proxies**: birth→cold-race→goal-prefix→HEAD-recompute→--short-drift→pane-name. Each instance patched; the *shape* recurs. | **effect-read**: assert the durable product (`type==assistant` turn present / `git log -1 %ct > T` / `.acked` cursor / `ls-tree` content), never mtime/HEAD-move/name/count. `effect-read-predicate-red-proof.md` |
| **D — deploy-lag / symlink-gap** | ~4 | **NONE (no reconciler exists)**. DEPLOY-NOW.sh does `merge --ff-only`, **no `ln -s`** (`DEPLOY-NOW.sh:35`). deploy-parity-assert = **detection-only**, `~/bin` copy-tools only. | **HIGH — filed 4×, all blocked**; accounts symlink (`e7bf7e6`) fixed one instance, new-file gap recurred (cc-crash-report, lr-reset-poller). | `git rev-list --count HEAD..origin/main` (behind) **+** `deploy-parity-assert.sh` (copy-drift) **+** *unbuilt*: `ls -la` parent dir vs tracked-files diff (new-file case has **no** detector) |
| **S — stranded output** | ~5 | Partial: v2 transport sound; v3 **P1 landed** (`e542db4`: forward-chains, --role, reroute, damping). **P3/P4 (human plane + lifecycle) BLOCKED.** | **HIGH** — v2 "sound transport" still lost 78%; recurred as wave-report-strand 3 days after the mail investigation. | `.acked < lines` guard (`cc-inbox-guard`, rides reaper) **+** disk-harvest by `agentName`; **missing**: statusline `📬N` badge + board comms-store (D10/D12, unbuilt) |
| **F — fail-open / blind-check** | ~8 | Partial + **the strongest structural precedent**: `premortem-gate.sh` ("a pre-mortem nobody can watch fire is a check that can't observe what it guards"; **abstain paths must emit {fired\|abstained:reason}**). RED-proof discipline catches instances at build. | **MED** — RED-proofs catch pre-land, but **new generators keep appearing** (stdin-eater, fixture-shape, esc_scan-grep, malformed-IDL). No generator-level lint. | grep the generator trio (`python3 - <<` + `stdin.read`; unused captured `$j`; `[ -f ]` not `[ -s ]`; grep without `--`) **+** one fixture from the producer's **literal** emission |
| **C — config/mechanism drift (built≠live≠firing)** | ~5 | **Partial — the key structural fix**: `idl-abstain-alarm.sh` ("abstained==100% over N≥10 ⇒ inert BY CONSTRUCTION"; log shows it flagged 4 DORMANT-100 hooks Jul-19 → healthy Jul-20). Covers **only 5 IDL hooks**, not the general case. | **MED-HIGH** — abstain-alarm generalization unbuilt; drift recurs (model-pin ignored, reaper registration-timing, ~/bin copy-rot). | `abstain-alarm` (per-hook fire-ratio) **+** `deploy-parity-assert` **+** the operator law: *mechanism, not memory; fail-loud on inertness* (`feature-durability…md:16-19`) |
| **W — wrong-causal-attribution** | ~4 | **NONE code-fixable** (reasoning failure). Only mitigation = discipline in memory (advisory → itself decays). One structural leaf: accounts `poll_throttled` flag vs "rate-limited" label (`013502f`). | **HIGH** — 3 wrong claims in ONE session (Jul-16) + reaper-blindness self-refutation + dispatch "correct wait state" masked bug. | Read transcript **last-assistant turns** before any causal sentence; for tools, expose the ambiguity as a **flag** not a **label** (`poll_throttled`, `stale_quota`, `INDETERMINATE⇒escalate`) |
| **X — crash / self-erasing evidence** | ~2 | Partial: de-conflated ledger + `classify_death` (`abdafc4`), `cc-crash-report` (`1ce427c`), version pin to 2.1.183. **Death mechanism still UNPROVEN** (stderr never teed). | Regression is **upstream (CC binary)** — pinnable, not code-fixable. Size-trigger prevention **surfaced not built**. | version-normalized crash-rate scan (`cc-crash-report --backfill`) **+** *unbuilt*: launcher stderr tee + transcript-size/RSS recycle trigger |

## (c) Filed-but-never-built list — "where filings go to die"

**The graveyard is the `block` state, and it's a one-way trip.** Backlog fold: 501 add / 482 done / **42 block / 80 reopen** → **currently 13 blocked, 10 open, 2 reopened**. The mechanism that *keeps* them dead is itself a filed-never-built silent failure:

- **`1603dbd083d7` — "cc-backlog unblock cannot stick — thrash fold ignores the unblock marker" (BLOCKED).** The unblock operation doesn't fold, so blocked items **cannot be revived** → block = permanent graveyard. This is the meta-mechanism of the whole pattern.

Silent-failure fixes currently **BLOCKED**:
- Deploy-symlink gap **filed 4×**: `761a546f939c`, `d83b624354af`, `2a51b6db07d3`, `7f9a3d014b10` ("link **39 unlinked tracked files**") — plus withdrawn dup `843ba1c25df1` (closed **done** without building the reconciler). The 45f412b commit confirms: *"already filed twice… both blocked on worker-landing thrash rather than on the gap being unknown."* Known ≥3× independently, still unbuilt.
- `02ba4e52389a` — mail v3 P1-P4 (P1 landed; **human-visibility P3 + lifecycle P4 blocked** — delivery still invisible to the human).
- `449f29fad085` — **desk-recycle-invariant (the fail-loud monitor) can't resolve the live desk process** → *the mechanism meant to catch silent decay itself silently fails.*
- `a3d505ff2cef` — "page() honors cc-notify rc" (silent page-failures unhandled).
- `28f54cf98aaf` — desk `.forward` strands reroutes.
- `6cab0ab3cb2f` — GC franchise (mailboxes/worktrees/pidfiles/tmp).

**OPEN (unstarted):**
- `1bba90389b79` — **transcript-byte/RSS recycle trigger** = the *primary* prevention for the crash class; explicitly *"surfaced not built — operator's call"* (`session-crash-diagnosis…md:87`).
- `1b784d80d4d5` — ship-land esc_scan grep fail-open.

**Pattern:** ~⅓ of blocked items are silent-failure fixes; they die because (a) the unblock is broken (`1603`), (b) landing-thrash starves them, (c) the prevention is a **live-armed-hook lifecycle change → operator C10 decision** the agent won't make unilaterally.

## Detection-lag distribution (Q4)

- **WORST (unbounded / permanent):** **S (stranded)** and **C (silent decay)** — a dead mailbox is *never* detected (some mail never consumed at all); a mechanism abstaining 1,309× is externally **indistinguishable from working** ("that is the entire trap," `feature-durability…md:14`). **D new-file** is invisible *"no matter how current the checkout"*.
- **WORST root-cause lag:** **X crash** (~11 days, 2 wrong theories) and **W** (confident single-observer claims that a transcript would have contradicted).
- **BEST (fast/pre-land):** **F fail-open** caught at *build* by RED-proofs (LR-c/LR-i before landing); goal-prefix caught same-session.
- **The determinant:** lag = how far the proxy sits from the durable effect-product. Watch mtime/name/HEAD/idle-notification → unbounded lag; watch `%ct`/`.acked`/assistant-turn/`ls-tree` content → sub-minute.

## (d) CANDIDATE FRONTIER PROBLEMS

**FP-1 — Deploy-lag as the meta-silencer (landed ≠ live ≠ linked)**
- **Evidence:** `deploy-lag-checkout-behind-origin.md:27-49`; `DEPLOY-NOW.sh:35` (ff-only, no `ln -s`); filed 4× all blocked (`761a546f939c`,`d83b624354af`,`2a51b6db07d3`,`7f9a3d014b10`); `deploy-parity-assert.sh:5-12`.
- **Mechanism class:** D (+ meta: silences fixes for *every* other class — a structural fix commit can be inert).
- **Current mitigations + status:** `rev-list` count + `deploy-parity-assert` (detection, `~/bin` copy-tools only); **no reconciler**; new-file case has **no detector**; unblock broken (`1603`).
- **Why it resists normal fixes:** deploy = **C10 human-only launchctl/ff-sync** boundary (agent must not self-deploy); no auto-reconciler; and the backlog that would schedule the build **can't unblock**. Recursive: the fix's own fix is stuck.
- **Quantified cost:** ½-session firefighting moot symptoms (Jul-20); 2-day stale-quota "weekly n/a"; near-silent fail-closure of the autonomy resume spine. **Measure:** count landed-but-unlinked tracked files (backlog says **39**) × mean days-to-live.
- **Frontier-fix sketch:** a `link-live.sh` reconciler (checkout→`~/.claude` per-file symlink diff) that runs as a **fail-loud parity gate at land-time** and **pages** on any unlinked tracked file; fold the new-file case into deploy-parity-assert; fix `1603` so the class can be unblocked.
- **Confidence:** HIGH / stale-risk LOW (verified on disk this session; DEPLOY-NOW.sh unchanged).

**FP-2 — Generalized silent-mechanism-decay detector (built≠live≠firing)**
- **Evidence:** `feature-durability-mechanism-not-memory.md:14` (1,309 abstains/0 fires under wrong config); `abstain-alarm.log` (4 DORMANT-100 hooks Jul-19); `premortem-gate.sh:8-12` (a check that can't watch itself fire).
- **Mechanism class:** C.
- **Current mitigations + status:** `idl-abstain-alarm.sh` (structural but **covers only 5 IDL hooks**); operator law "mechanism not memory, fail-loud on inertness" (advisory).
- **Why it resists:** a decayed mechanism is **externally identical to a working one**; you cannot enumerate every mechanism to watch; config-dir migrations (.claude→-quaternary) strand arms invisibly. Detection needs a *self-registering* fire-ratio census, not a hand-maintained list.
- **Quantified cost:** days of no-auto-recycle; **feeds the crash class** (unrecycled sessions bloat). **Measure:** per-mechanism fire-ratio over N≥10 invocations across all config dirs.
- **Frontier-fix sketch:** every hook/daemon self-registers a heartbeat `{fired|abstained:reason}`; a census alarms on `abstained==100% over N≥10` **or `invocations==0 over T`** (the harder "never even evaluated" case); config-dir-agnostic.
- **Confidence:** HIGH / stale-risk LOW.

**FP-3 — No external→model wake floor (78%-unacked stranded delivery)**
- **Evidence:** `cross-session-mail-2026-07-20.md:47-59,102-131` (0 watchers/16 live; harness floor: no external process wakes an idle CC session without keystrokes or a pre-armed task); `wave-report-harvest-from-disk.md:11` (idle≠delivery); backlog `02ba4e52389a` (P3/P4 blocked).
- **Mechanism class:** S.
- **Current mitigations + status:** v3 P1 landed (addressing); **P3 human-plane + P4 lifecycle BLOCKED**; delivery still invisible to the human; `additionalContext` is model-only.
- **Why it resists:** it is a genuine **harness limitation**, not a code bug — the only external→model wake is the background-task-completion notification, which the model must **arm on itself**. No standing floor can be imposed from outside.
- **Quantified cost:** 1,401 unacked lines; decisions un-relayed 30min+; wave synthesis stalls. **Measure:** unacked-lines and dead-box age at survey (already instrumented).
- **Frontier-fix sketch:** resident-rule + `cc-wait` contract that *every owned wait arms `cc-await-ping`* (heartbeat proves it) + PostToolUse mid-turn drain (pending live-probe) + statusline `📬N` + board comms-store — i.e., a self-armed standing watcher as an **invariant**, not a convention.
- **Confidence:** HIGH / stale-risk MED (P3/P4 could land; re-check backlog `02ba4e52389a`).

**FP-4 — Self-erasing crash evidence + upstream version-regression**
- **Evidence:** `session-crash-diagnosis-2026-07-22.md:20-48,85-99`; `session-crash-per-session-bloat.md:11-25` (**empirical** 8,637-transcript scan: 0.02%→4.76%→1.56% by version; **theory flipped twice**: OOM/bloat → version regression); death mechanism **UNPROVEN**.
- **Mechanism class:** X.
- **Current mitigations + status:** de-conflated ledger + `classify_death` (`abdafc4`); `cc-crash-report` (`1ce427c`); pin to 2.1.183 (**primary lever**); size-trigger prevention **OPEN** (`1bba90389b79`).
- **Why it resists:** the fatal event **destroys its own evidence** (process death before stderr flush; no `.ips`); root cause is **upstream in the CC binary** (pinnable, not repo-fixable); the recycle that would cap size is **blind to size** (fires on context%, not bytes).
- **Quantified cost:** lost 60MB+ sessions; ~11-day misattribution; **the "abrupt closes" the operator opened this whole thread on.** **Measure:** `transcript_kb` + `claude_version` per crash (now logged).
- **Frontier-fix sketch:** launcher **tees `claude.exe` stderr per-pid** (names JSC-heap-OOM vs internal-limit vs `/compact`-crash GH#49593); add a **transcript-byte/RSS recycle trigger** to `waiting-recycle.sh`; a per-CC-version conformance probe on every binary bump.
- **Confidence:** MED / stale-risk **HIGH** — this is the youngest, twice-revised finding; the version-regression verdict is 2026-07-23-fresh and the mechanism is explicitly unproven. **Re-verify before acting.**

**FP-5 — Proxy-verification generator class (verify-by-proxy keeps regenerating)**
- **Evidence:** `effect-read-predicate-red-proof.md`; `desk-monitor-fixed-head-ref.md:14,33-42`; `cc-notify-session-pane-mapping.md:18-24`; `desk-read-transcript-before-asserting-why.md` (3-in-one-session).
- **Mechanism class:** P + W.
- **Current mitigations + status:** per-instance patches (`ef11307`, `ad37447`, sessionId-only) + the RED-proof discipline (memory, advisory → decays).
- **Why it resists:** it is a **reasoning/idiom failure**, not one bug — every new monitor/verify introduces a *new* proxy (mtime, HEAD, --short, name, birth, idle-notification). No single patch closes the class; the fix is a **habit** that memory can't durably enforce.
- **Quantified cost:** 3 wrong causal claims/session; near-interrupt of a working lead ×2; 33-min unreached successor. **Measure:** count causal claims sourced to indirect signals per session (currently unmeasured).
- **Frontier-fix sketch:** a lint/rule that flags any monitor comparing mtime/HEAD/name/count as a **liveness/causal** signal without a paired durable-product read; a `verify-fresh` helper library every mutation/verify must call; generalize the effect-read predicate into shared tooling so the correct idiom is the path of least resistance.
- **Confidence:** MED-HIGH / stale-risk LOW (pattern is stable and well-evidenced).

---

**Adversarial-pass integrated (findings above already fold these):** (1) counted *incidents* not *files* — `desk-read-transcript` alone = 3, `cross-session-mail` = 42 boxes; (2) flagged that "structural fix exists" **inherits deploy-lag** — a landed fix (e.g. `ad37447`) can be silently inert (FP-1 is the meta-silencer); (3) marked **empirical vs theoretical** on every revised finding (crash class flipped twice; reaper-blindness theory self-refuted); (4) verified `DEPLOY-NOW.sh`/`deploy-parity-assert.sh` on disk rather than trusting memory; (5) split fail-open into *fail-on-error* vs *structurally-blind-check* but kept them one class per the brief's starter set.

**Blockers / uncertainties:** memory files carry point-in-time staleness warnings (cross-checked against git + live backlog where load-bearing). Crash-class verdict (FP-4) is 1-day-old and mechanism-unproven — highest stale-risk. Detection-lags for W/P are estimated (intra-session) not instrumented. Backlog block-reasons were sparse in the event log (few `reason` fields), so "why blocked" leans on the 45f412b narrative + `1603` unblock-broken finding rather than per-item reasons.