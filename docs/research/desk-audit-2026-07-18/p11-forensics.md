# P11 — Orchestrator-Desk Incident Forensics (FM1 premature-done / FM2 idle-standoff)

**Beat:** empirical ground truth of the two failure modes, reconstructed from transcripts/memory/git — not theory.
**House rule applied to self:** every causal claim below is tagged **[grounded: <ref>]** (read a transcript line / hook code / log) or **[inferred]** (evidence-consistent but not directly read). Indirect signals (mtime/HEAD/file-appearance) show WHAT, never WHY.

**Retention window:** JSONLs 2026-06-10 → 2026-07-18 (~5.5 wk), 9595 files across 5 account dirs (`~/.claude`, `-secondary`, `-tertiary`, `-quaternary`, `-next`). **The desk runs on `.claude-tertiary`** — all incident `originSessionId`s resolve there. Incidents before 06-10 (tp-assignee, 2026-05-03) are PRUNED → CLAUDE.md-sourced only.

---

## 1. Incident Dossiers

### INC-1 — Three misrouted cc-notify nudges (2026-07-16)
| Field | Value |
|---|---|
| Source | memory `cc-notify-session-pane-mapping.md`; session `4bee0fc1` (tertiary) [grounded: transcript exists, desk-spawn prompt @ line 14] |
| Signal desk had | `cc-notify --list` friendly name `doc_classifier-D52E76B7` + pane age + cwd |
| Conclusion drawn | "successor session is in pane D52E76B7" → nudged it 3× (un-stick/take-over/escalate) |
| Ground truth | `--json` showed D52E76B7 = the **fix-w6 teammate** (session 35c6b6ce); the successor (ec3450bd) was in pane **51609A98** (the prior lead's pane, kept across in-place `/handoff`). Every nudge hit the hung teammate; successor sat 33-min owned-wait receiving nothing [grounded: memory §Why, transcript-confirmed spawn context] |
| Root cause | **Pane identity ≠ session identity** after in-place recycle; mtime bump on `bridge-session`/`mode` entries misread as "it woke" |
| Current asset that would catch it | **NONE structural.** Discipline only: resolve via `--list --json` sessionId. `cc-notify` has no guard forcing sessionId resolution. Recurs if a successor desk skips the discipline. |

### INC-2 — False stall/RECYCLE_NOW fired twice (2026-07-16)
| Field | Value |
|---|---|
| Source | memory `desk-monitor-fixed-head-ref.md`; session `4bee0fc1` (tertiary) [grounded] |
| Signal desk had | Ad-hoc monitor doing `BASE=$(git rev-parse HEAD)` **recomputed at each re-arm** |
| Conclusion drawn | "HEAD unchanged for window → lead stalled → RECYCLE_NOW" (×2) |
| Ground truth | Lead had just committed `b3b0e82` then `24b14ed`; the re-arm captured the already-advanced HEAD as BASE, so it reported "no movement" for a working lead. A blind recycle would have interrupted mid-flight [grounded: memory §Why] |
| Root cause | **Moving reference** — BASE recomputed instead of a FIXED last-witnessed ref. Companion bug (07-17): `git rev-parse --short` abbreviation GROWS as objects accrete → same commit reads as a false MERGE |
| Current asset | **NONE standing.** No persistent fixed-ref monitor exists; the desk hand-writes the monitor each session. Discipline (`desk-monitor-fixed-head-ref.md`) is the only guard. |

### INC-3 — Three wrong causal claims: false rate-limit, false "resumed on its own" (2026-07-16)
| Field | Value |
|---|---|
| Source | memory `desk-read-transcript-before-asserting-why.md`; sessions `68aeeab0`/`4bee0fc1` (tertiary) [grounded] |
| Signal desk had | (a) bare `429` grep of a transcript + `claude-accounts` poll-throttle label; (b) an `index.html` appearing |
| Conclusion drawn | (a) "next2/next3 rate-limited → quota-stalled"; (b) "marquee resumed on its own" |
| Ground truth | (a) all 4 accounts 0–24% session / 0–23% weekly; `429` false-positives from UUIDs/token-counts; (b) the marquee lead's `model:"fable"` override was silently ignored (ran Opus), spawn hung ~35 min in "Hatching", and the **OPERATOR manually resumed+redirected it** [grounded: memory §Why, both root causes] |
| Root cause | **Cause inferred from side-effect** (WHAT-changed ≠ WHY). Same family as INC-1 (mtime) and INC-2 (HEAD). |
| Current asset | **NONE — un-encodable in code.** Pure discipline: read last `"type":"assistant"` turns before any causal claim. This is the load-bearing house rule; nothing enforces it at the harness. |

### INC-4 — Cold `--worktree` fire never engaged (2026-07-17)
| Field | Value |
|---|---|
| Source | memory `cold-worktree-fire-autosubmit-race.md`; session `9f1c9526` (tertiary) [grounded] |
| Signal desk had | `handoff-fire.sh --worktree` printed "→ fired … (cold)" |
| Conclusion drawn | "session fired, working" |
| Ground truth | Auto-submit keystroke raced CC boot; session sat at empty prompt, **never read the brief**. 0 commits, no file activity, no ping. Only the desk's own transcript contained the brief text (it wrote the file) [grounded: memory detect-clause] |
| Root cause | Cold-worktree provisioning delay > auto-submit timing; **no wait-for-boot / verify-engagement** in the fire path |
| Current asset | **PARTIAL / mostly OPEN.** `1608650` fixed pkg-manager detection in cold bootstrap (one contributing delay). **`handoff-fire.sh` still has NO engagement-verification** [grounded: grep of `scripts/handoff-fire.sh` — `--self-retire` present @ line 84, zero `verify-engag`/`wait-for-boot` matches]. Reaper backstop cannot see the orphan (INC-7 registry gap). Discipline: prefer warm `--cwd`, verify by transcript content. |

### INC-5 — Dropped commit dfacccd (2026-07-11)
| Field | Value |
|---|---|
| Source | `.claude/CLAUDE.md` incident note; memory `reference-landing-safety-tooling.md` [grounded]; `git show -s dfacccd` = "feat(limit-recover)" now present on trunk [grounded: git] |
| Signal desk had | `git rev-list origin/main..HEAD` = 0 |
| Conclusion drawn | "looks landed" |
| Ground truth | A sibling `/ship` rebase-land silently dropped `dfacccd` (5 limit-recover files) while count read 0; files were **absent from main** though count said clean |
| Root cause | Concurrent-land race in a shared checkout; **verify-by-count instead of by-content** |
| Current asset | **CAUGHT TODAY (only incident with a solid CODE fix).** `land-lock.sh` (repo-keyed mutex) + `stranded-sweep.sh` (content-absent scan via `git cherry`+`ls-tree`) + project-local `/ship` (lock→refetch→rebase→gate→push→**content-verify**→stranded-sweep), landed `f3ab48a`. Rule: prove content with `git show <trunk>:<path>`, never count [grounded: memory; "would catch" is design-level, not re-run] |

### INC-6 — tp-assignee teammate crash (2026-05-03)
| Field | Value |
|---|---|
| Source | `CLAUDE.md` Agent-Teams section only; **transcript PRUNED** (< 06-10 floor) [grounded: retention] |
| Ground truth | A `/compact` crashed a teammate (GH #49593) mid-task |
| Root cause | Over-large brief → `/compact` → crash; teammate lifecycle, **not a desk FM1/FM2** |
| Current asset | Process discipline: brief ≤150 lines, pre-grep line ranges, preventive splitting in Phase 0. No harness enforcement of brief size beyond the `agent-teams-enforce` PreToolUse pointer. |

### INC-7 (canonical FM1/FM2) — Five fired peers idle + Hammerspoon orphan (2026-07-17)
| Field | Value |
|---|---|
| Source | memory `desk-spawned-session-lifecycle-discipline.md`; sessions `68aeeab0`/`933db1a0` (tertiary) [grounded: `933db1a0` assistant turn "Both **finished their work, then deferred a trivial pre-authorized step** ('say the word'…)"] |
| Signal desk had | Peers pinged `DONE`, then their JSONLs went quiet |
| Conclusion drawn | (implicitly) "done = closed" |
| Ground truth | **Hammerspoon** peer self-declared "Complete — nothing to do" and **orphaned idle** (brief omitted the ping). **Five peers** (Phase-4, dmarc, azure-100, tokenomics, reaper-polish 59664) pinged then **sat IDLE**, each deferring a trivial pre-authorized tail (push/ff/land) on "say the word"/"heads-up" — **the deference reflex propagated INTO fired sessions.** Stream-B variant: built+committed, then **hung 35+ min on the final LAND** (alive, uncommitted-to-trunk, no gate child) [grounded: memory §§1,3,5] |
| Root cause | **FM1** (premature-done + deference on drivable tails) compounded by spawn-brief inconsistency |
| Current asset | **Mostly OPEN.** `f137b1b` self-retire DEFAULT closes peers that REACH completion [grounded: handoff-fire.sh line 84] — but not a mid-land hang. Anti-deference hook is DEAD (§4 G-P11-1/2). Reaper has the registry gap. |

---

## 2. Signatures

### FM1 signature (premature-done / purpose-loss) — the recurring shape
A session's **last assistant turn** either (a) **asserts done** ("Complete — nothing to do", "📦 Done, but only on local main") or (b) **presents drivable pre-authorized work as a question/hold** ("say the word", "want me to", "your move", "holding … for your go"), **AND** at least one is true: uncommitted in-scope work exists · committed-but-unlanded **verified net-positive** work exists (`trunk..HEAD>0`, clean tree) · frozen-scope remainder ≠ none — **AND** no *genuine-three* blocker is actually present (external-info-only-operator-has / value-fork-standing-values-don't-settle / a true C10 like a credential — **ship/land is NOT genuine** under the 07-17 strengthening).
Minimal flagging predicate: `(done_assertion ∨ deference_tell) ∧ (uncommitted ∨ unlanded_verified ∨ scope_remainder) ∧ ¬genuine_three`. **Operator ground truth [grounded: session 8a34082e]:** *"'Your move'. No, you should know that you need to drive all this autonomously with no human in the loop, and the fact that you didn't concerns me."*

### FM2 signature (idle-standoff / mis-state) — the recurring shape
The desk **asserts a WHY about a watched session's state** (working / owned-wait / stuck / rate-limited / resumed / done) from an **indirect signal** — JSONL mtime, git HEAD move, a file appearing, a bare-string grep, or pane-name/age — **without** the three groundings. It is wrong because ≥1: metadata entries (`mode`/`permission-mode`/`bridge-session`/`system`/`ai-title`) bump mtime with no turn · pane identity ≠ session identity after in-place recycle · HEAD recomputed-at-rearm ≠ fixed witnessed ref (and `--short` drift) · a lead at an **owned-wait** on teammates looks idle · a committed-but-unlanded peer looks finished · a cold fire that never engaged looks "fired".
Minimal flagging predicate: a state/causal claim is **ungrounded** unless backed by ALL of `{last "type":"assistant" turn read, session resolved via --list --json sessionId, HEAD-diff vs a FIXED witnessed ref}`. **No code enforces this** — it is the `desk-read-transcript-before-asserting-why` + `cc-notify-session-pane-mapping` + `desk-monitor-fixed-head-ref` triad, all discipline.

---

## 3. Frequency Estimate (honest, small-N)
- **Operator ground truth [grounded: memory desk-spawned-lifecycle §Two-recurring-failures]:** FM1/FM2-class failures "**multiple/day, all week**", called out 2026-07-17. b9b2804 commit msg: deference "flagged **4×**".
- **191 supervisor page files** (`~/.claude/autonomy/pages/*.page`) = past-threshold escalations (sessions stuck past their context threshold without self-recycling) over the telemetry window [grounded: `ls | wc`].
- **53 waiting-recycle `dirty-tree-hold` abstains** = an armed desk hit a recycle boundary with **uncommitted work** 53 times [grounded: IDL].
- **anti-deference: 176 invocations, 0 fires** = 0% demonstrated FM1 catch-rate [grounded: IDL].
- **cc-reaper: 0 reaped / every 5-min sweep** (4/18/33/22 classified, 0 candidates) [grounded: `cc-reaper.log`].
- **Denominator caveat:** the session-index DB (4981 sessions; only **53** tagged claude-infrastructure, of which **1** has swept content) is NOT a reliable content-frequency source — desk/worktree sessions run under many encoded project paths and age out. A clean "% ended unclosed" is unrecoverable from the index; the numbers above are the best-grounded proxies.

---

## 4. Gaps & Fragilities
| ID | Evidence ref | FM | Sev | One-line failure scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P11-1 | IDL: 176 inv / 0 fire / 113 `no-assistant-text`; transcript `343c6e77` last turn tool_use-only, tail = mode/permission-mode/bridge-session [grounded] | FM1 | P0 | Anti-deference hook can't read a turn that ends on a tool_use or has a metadata tail → misses the deference | Walk back past metadata/`tool_use`-only entries to the last text block in the last N assistant entries before abstaining |
| G-P11-2 | Post-landing turns `9f1c9526`/`23fe72e2`: "📦 Done… **say the word** (/ship or push) to land"; hook GENUINE regex carves out push/land as C10 [grounded: hook lines 86–88 + IDL 0-fire] | FM1 | P0 | The desk's #1 deference (park-then-ask-to-ship) is exactly what the hook is built to ignore, contradicting the 07-17 "ship verified net-positive work" strengthening | Narrow C10 carve-out: push/land is NOT genuine when tree clean ∧ work verified+net-positive; keep sudo/credential/destructive-migration/value-fork genuine |
| G-P11-3 | INC-7 Hammerspoon "Complete — nothing to do"; hook TELLS lack done-assertions [grounded: hook line 81] | FM1 | P1 | A premature-done orphan that declares done (no question) never triggers the hook | Add done-assertion tells gated on `scope_remainder ∨ uncommitted ∨ unlanded_verified` |
| G-P11-4 | memory lifecycle §4 "cc-reaper sweep never listed it"; `cc-reaper.log` 0 reaped/sweep; grep of `bin/cc-reaper` = no handoff-fire enumeration [grounded] | FM2 | P0 | Desk-spawned orphans — the exact FM2 class — are invisible to the standing reaper net | Enumerate live handoff-fire panes (ITERM_SESSION_ID/`ps`-based), not just the cc-sessions registry |
| G-P11-5 | `scripts/handoff-fire.sh` has `--self-retire` but zero `verify-engag`/`wait-for-boot` [grounded: grep] | FM2 | P1 | A cold `--worktree` fire prints success but never engages; desk believes a working session exists | verify-engagement (poll target transcript for brief-text/first turn) before declaring a fire successful; auto-refire warm on miss |
| G-P11-6 | INC-1/2/3 all discipline-only; no `cc-notify`/monitor guard [grounded: absence] | FM2 | P1 | A successor desk that hasn't internalized the memory repeats the misroute / false-RECYCLE / false-cause trio | A `desk-assert` helper that refuses a causal/state claim unless backed by {assistant-turn read + `--json` sessionId + fixed ref} |
| G-P11-7 | IDL: waiting-recycle 971 inv / 0 fire / 714 `not-armed` [grounded] | FM1/24×7 | P2 | A desk that never arms waiting-recycle is unguarded against context-rot purpose-loss (an FM1 root); fire path unproven in prod | Arm-by-default when the spawn brief marks a session "monitoring-desk"; add a fire-path smoke test |
| G-P11-8 | `cc-reaper.err.log`: `command not found: cc-reaper` ×4 (un-timestamped) [grounded: log] | FM2/24×7 | P2 | A lingering bare-name resolution path could silently no-op a sub-invocation despite 36f9d64 | Audit internal cc-reaper self-calls for absolute paths; timestamp err lines to confirm pre/post-36f9d64 |

---

## 5. Task Candidates
| ID | Action | Acceptance criterion | Depends-on |
|---|---|---|---|
| T-P11-1 | Robust last-assistant-text extraction in `anti-deference-nudge.sh` | IDL `no-assistant-text` rate on desk sessions → ~0; hook evaluates the real final text | G-P11-1 |
| T-P11-2 | Reframe C10 carve-out: ship/land not-genuine when verified+net-positive | Hook FIRES on "say the word on ship" for clean-tree committed net-positive work; still abstains on credential/sudo/value-fork | G-P11-2 (after T-P11-1) |
| T-P11-3 | Scope-aware done-assertion tells | Hook fires on "Complete — nothing to do" when `trunk..HEAD>0 ∨ scope_remainder≠none` | G-P11-3 |
| T-P11-4 | cc-reaper enumerates handoff-fire panes | A fired-then-orphaned peer appears as a reap candidate; e2e reaps a synthetic fired orphan | G-P11-4 |
| T-P11-5 | handoff-fire verify-engagement gate | A cold `--worktree` fire that fails to engage is detected + auto-refired warm; guard test | G-P11-5 |
| T-P11-6 | `desk-assert` guard helper (refuse ungrounded causal claim) | A causal claim lacking the 3 backings is blocked/flagged in a desk self-check | G-P11-6 |

---

## 6. Adversarial Self-Pass (are my causal claims grounded?)
- **"Anti-deference never fires because of extraction miss"** — PARTIALLY grounded. Read `343c6e77` (tool_use-terminal, metadata tail) → mechanism confirmed for that class. BUT the 74% `no-assistant-text` is dominated by teammate/worktree-pool Stop events (e.g. `wt-pool-3`), NOT proven per-instance on a real desk-deference turn. The **carve-out** miss (ship/land) IS demonstrated by reading the hook's TELLS + GENUINE regexes against `9f1c9526`/`23fe72e2` text with IDL showing 0 fires. Net claim "hook provides ~zero real FM1 coverage" rests on {0/176 fires + 39 no-tell clean-evals + demonstrated ship carve-out + operator says deference recurred}, which jointly contradict "no deference occurred." Kept, tagged.
- **"Reaper reaps 0 due to registry gap"** — grounded (memory explicit + log 0-reaped + grep absence). Strong.
- **"Cold-fire race still open"** — grounded (grep: self-retire present, verify-engagement absent).
- **"Dropped-commit caught today"** — design-level; I did NOT re-run stranded-sweep. Tagged.
- **What a hostile reviewer would say I missed, and what I then checked:** (a) *"waiting-recycle 0-fire = broken?"* → checked reasons: 714 `not-armed` (opt-in by design) + 53 `dirty-tree-hold` (correct SAFE hold) → 0-fire is largely defensible, re-scoped to G-P11-7 (unproven, not broken). (b) *"Is the reaper even alive?"* → checked launchd: `com.chrisren.cc-reaper` loaded, StartInterval 300, healthy sweeps in `cc-reaper.log` → FM2 net is LIVE (unlike FM1's dead hook), the gap is enumeration not liveness. (c) *"Are the incident transcripts real or just memory?"* → located all 5 originSessionIds on tertiary + spot-confirmed spawn prompts and the `933db1a0` five-peers-deferred line.

## 7. Uncertainties
- Per-instance anti-deference miss mechanism (extraction vs carve-out) not proven for every abstain; extraction grounded-but-not-per-desk-instance, carve-out demonstrated.
- `cc-reaper.err` "command not found" lines are un-timestamped → can't confirm they're pre-36f9d64 residue vs a live residual path.
- Frequency lacks a clean denominator (index content-sweep incomplete for infra/worktree sessions) → reliant on operator "multiple/day" + proxies (191 pages, 53 dirty-holds, 0/176 fires, 0/sweep reaps).
- `session-continue.sh` actuations don't appear in this IDL → the auto-continue arm of FM1-prevention is unmeasured here.
- waiting-recycle fire path (context-rot self-recycle) has **never executed in prod** (0/971) → its FM1-prevention efficacy is unproven.
