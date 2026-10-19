# Slot A: how wrap-ledger computes the rung, and why a research-only close reads ✅

Worktree HEAD 36afca47f. `scripts/wrap-ledger.sh` was last touched at a6f48eda7 and is 3043 lines (`wc -l`).
Incident transcript: `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-192325-42328/74728043-….jsonl`, abbreviated **T** below. Its cwd is `/Users/chrisren/Development/.worktrees/wt-cc-192325-42328`, a worktree of claude-infrastructure-private.
Scratch scripts are in `/tmp/rpic-A-ledger/`. The sandbox is `/tmp/rpic-A-ledger/sbx.ay3oPi`.

## 0. Answer first

1. **Why the close read ✅.** The ledger checks one predicate per rung. Each predicate reads git state, or a store that **this session wrote to**. The incident session committed nothing, so git read clean and landed. It filed no backlog row and opened no packet before the close at T:464.
   - Every session-scoped term therefore read 0: BLOCKED, UNCONVICTED, FILED_MINE and YOURS.
   - ⛔ counts only packets with `session_sid == $SID` (`wrap-ledger.sh:1500`). The 58 open class-C packets carry 22 other session ids, and none is this session's. (These are today's store figures; the incident saw 74 open.)
   - SCOPE read **`met` over zero items**. The repo-key DoD file is shared by every claude-infrastructure worktree. For this cwd the lineage filter keeps 16 old, unattributed blocks that contain **0 checkboxes**. `DOD=present` is set when the *file* exists (`:905`), and `REMAINDER=0` gives `SCOPE=met` (`:938-940`).
   - With every arm false, the initial assignment at `:2492` survives: `READOUT="✅ Complete & live on trunk — nothing to do."`
2. **Nothing in the ledger can see "research done, implementation pending".** No input holds the fact:
   - `RESEARCH_*` only covers registered programs, and it is "REPORTED, NEVER A RUNG" (`:180-190`, `:2497-2499`).
   - The goal term is a report only (`:155`, `:2493-2496`), and T has no goal records.
   - The only rung that means "the operator must act" is 👤. It counts only `cc-backlog --blocked` rows that this session filed (`:1298-1327`).
3. **Reproduced in a sandbox (§4).** Five open class-C packets whose `session_sid` is another session give `BLOCKED=0 RUNG=✅ READOUT=✅ Complete & live on trunk — nothing to do.` A DoD made only of a foreign `Scope (frozen):` block with no boxes gives the same result, with `SCOPE=met`.
4. **Narrowest insertion point.** A new `elif` arm inside the ✅-eligible chain, between the 👤 arm (`:2618-2626`) and the DoD-absent arm (`:2627`). If the pending implementation is the agent's own to drive (reversible, low-stakes), the arm should instead sit in the 🔧 band beside FILED_MINE and UNCONVICTED (`:2563-2574`).
   - Either way it needs a **new session-scoped producer record**. None of today's stores carries one: the session read 74 packets and wrote nothing.
   - Any non-✅ rung already withholds both SAFE TO CLOSE surfaces (`operator-readout.sh:2113`, `:2138`).

## 1. Where the two strings come from

| String | Source | Kind |
|---|---|---|
| `✅ Complete & live on trunk — nothing to do.` | `scripts/wrap-ledger.sh:2492`: the *initial* `RUNG="✅"; READOUT=…`, left as is when no arm of the ladder fires | computed (by default) |
| `complete — nothing to do` (`--full` "Next:" row) | `wrap-ledger.sh:2998` (`rung_next`) | computed |
| `Good to close: yes — nothing of mine is open; follow-on: …` | `hooks/lib/close-shape.sh:179` (`close_shape_template`, the S2 line-1 skeleton), also `hooks/lib/why-tier.sh:172-173` (the "shape" WHY text) | **template prose the model fills in**; nothing computes it |
| `✅ SAFE TO CLOSE — nothing of mine is open` | `hooks/operator-readout.sh:1352`, the header state on ✅ when `CERT_WROTE=0 ∧ scope=met ∧ verdict≠no` | computed, but did NOT render in the incident (see §3) |

The model copied the ledger readout as line 2 (T:461 `READOUT=✅ Complete & live on trunk — nothing to do.`, then T:464). It took line 1 from the close-shape template. The template offers only two verdicts: "yes — nothing of mine is open" and "no — <what remains + who owns it>". **Neither has a slot for "research done — implementation pending your sign-off".** At T:307-390 the model correctly answered `❌ Good to close: no … (mine to collect)` while agents were still running, and switched to "yes" once they returned.

## 2. Rung and readout: inputs and evaluation order (`--machine`)

### 2a. Inputs, computed before the ladder

| Input | Lines | Predicate / source | Fail direction |
|---|---|---|---|
| TRUNK | 764-810 | `WRAP_TRUNK` > `git config claude.trunk` (verified) > `symbolic-ref origin/HEAD` > origin/main > origin/master; then `rev-parse --verify` or "" | "" ⇒ the no-trunk 🔧 arm |
| DIRTY / DIRTY_N | 828-830 | `git status --porcelain` line count | — |
| AHEAD / CHERRY / UNLANDED | 833-840 | `rev-list --count TRUNK..HEAD`; `git cherry` '+' | — |
| LANDING | 849-861 | `hooks/lib/land-inflight.sh::land_inflight_live` | — |
| GATE | 863-869 | gate-green sha == HEAD. Reported only, never a rung (2464-2491) | — |
| DOD / REMAINDER / DOD_SCOPE / DRAIN_SCOPE | 871-935 | `dod_read_files`, then the **lineage-filtered** content (`dod_filter_for`). `DOD=present` iff **any source file exists** (905). REMAINDER = count of `- [ ]` lines | file absent ⇒ `DOD=absent` |
| SCOPE | 936-940 | absent ⇒ `unknown`; REMAINDER>0 ⇒ `open`; else `met` | **"met" does not require that any box exist** |
| SID | 496-504, 950 | `--session` > `WRAP_SESSION_ID` > `CLAUDE_SESSION_ID` > `CLAUDE_CODE_SESSION_ID` | "" ⇒ every session term reads `none`/0 |
| GOAL_* | 993-1042, called at 2496 | `goal-state.sh::goal_liveness` over the transcript. **Never consumed by the ladder** | none/error/absent |
| RESEARCH_PROGRAM/VERDICT/PENDING | 1048-1089, called at 2499 (machine/full only) | `rp_resolve_cwd $PWD` against `programs.json`, then `cc-research verdict --json`. **Never consumed by the ladder** | none/unknown |

### 2b. The ladder (`:2492-2660`), in evaluation order

| # | Rung | Predicate | Lines | Computed where |
|---|---|---|---|---|
| 0 | ✅ default | `RUNG="✅"; READOUT="✅ Complete & live on trunk — nothing to do."` | 2492 | — |
| 1 | ⛔ | `BLOCKED>0`: open class-C packets with `.session_sid==$SID` AND (producer set ∨ created<epoch ∨ conviction+receipt) | 2504-2511; fn 1483-1524 (jq 1499-1508) | **unconditionally**, every close |
| 2 | 🔧 | `DIRTY==1` | 2512-2513 | |
| 3 | 🔧 | `REMAINDER>0` | 2514-2515 | |
| 4 | 📦 | `UNLANDED==1` (two sentences: land in flight / unlanded) | 2516-2522 | |
| — | *✅-eligible* `else` | everything below is computed only here | 2523 | |
| 5 | 🔧 | `CUSTODY_OPEN>0` (pane-attributed mine+unattributable, or cwd count) | 2530-2543; fn 1578-1615 | |
| — | compute | `[ -n TRUNK ] && compute_live_layer; count_operator_steps`; `count_filed_undriven; compute_close_floor; sum_unconvicted; count_resident_members` | 2545-2549 | |
| 6 | 🔧 | `RESIDENT_MINE>0` (live teammate processes from this session's team config) | 2550-2562; fn 1689-1746 | |
| 7 | 🔧 | `FILED_MINE>0` (open rows `.filedBy==$SID` with no whyNotNow/condition) | 2563-2566; fn 1396-1438 | |
| 8 | 🔧 | `UNCONVICTED_MINE>0` (needs-human rows or class-C packets of mine with no conviction or receipt) | 2567-2570; 1442-1450 + 1499-1514 | |
| 9 | 🔧 | `CLOSE_FLOOR==1` (DRAIN_SCOPE ∧ CLOSED_MINE==0) | 2571-2574; fn 1471-1481 | |
| 10 | 🔧 | `TRUNK==""` (landing unproven) | 2575-2585 | |
| 11 | 🚀 | `LIVE_BREACH==1` (4 sentences: mig failed / diverged / adds / time / commit) | 2586-2617; fn 2107- | |
| 12 | 👤 | `YOURS>0` (blocked rows `.session==$SID` or a fired peer's, excluding unconvicted needs-human) | 2618-2626; fn 1298-1327 | |
| 13 | ✅ variant | `DOD==absent` ⇒ "✅ Clean & landed — completeness UNKNOWN…" | 2627-2631 | |
| 14 | ✅ variant | `LIVE_SRC==behind` ⇒ 4 "✅ Complete & landed — live layer converging…" sentences | 2632-2657 | |
| 15 | ✅ default stands | none of the above | (2492) | |

After the ladder come BUSY (`:2662-2679`) and LINK_STRAY (`:2681-`), both "REPORTED FIELDS, NEVER A RUNG". The emitter is `emit_machine`, `:2736-2817`. The memo key (`:624-640`) includes the transcript mtime, so any new transcript-derived input is invalidated for free.

**Consequence of the order.** Row 15 (the incident string) needs all of these at once: no session-attributed packet, clean, REMAINDER=0, landed, no custody/resident/filed/unconvicted/floor, trunk resolved, no live breach, YOURS=0, **DOD present**, and LIVE_SRC ≠ behind. If DOD had been absent, row 13 would have read "completeness UNKNOWN" instead.

## 3. Why the incident landed on row 15: input by input

Measured on the live stores, read-only, at about 2026-10-19T03:30Z. The incident close was T:464 at 02:37:19Z.

| Input | What it read | Could it have seen the pending work? |
|---|---|---|
| DIRTY/UNLANDED | clean, landed. The session wrote only `/tmp/xd/*.md` (T:456 `cd /tmp/xd && … > REPORT.md`) | No. The output was never in a tracked tree. |
| BLOCKED (⛔) | 0 | **No, by design.** Store: `jq 'select(.status=="open")' ~/.claude/autonomy/decisions/*.json` ⇒ C=58, B=1 open. Of the open class-C packets, **0** carry sid `74728043…` or its predecessor `f06b5e9b…`, and they span **22 distinct** session_sids (top: f1274fba=15, 5688712d=11, d7eb73d2=7). The session *re-checked* them; it OPENED none. Transcript scan (`/tmp/rpic-A-ledger/tools.py`): up to T:464 there are 0 `cc-decide open`, 0 `cc-backlog add/needs`, 0 `git commit`. All 12 `handoff-fire`, 3 `cc-decide action` and the one `cc-decide open` mention are at T:541-670, after the operator's reply. The `session_sid==$SID` match is the alarm-polarity guard (`:46-51`): counting the standing pile would fire at every close. |
| UNCONVICTED | 0 | No. Same `$mine` set (`:1500`). |
| FILED_MINE / YOURS / CLOSE_FLOOR | 0 / 0 / n-a | No. The session filed no rows. DRAIN_SCOPE keys on the DoD scope text, which was foreign (below). |
| CUSTODY / RESIDENT | 0 | No. The 9 research agents were in-process `Agent` subagents (tool count: Agent=9, Bash=56, Write=1). Custody covers handoff-fire dispatches, and RESIDENT covers team members. |
| **SCOPE** | **met (vacuous)** | **This input should have abstained.** `/tmp/rpic-A-ledger/dod2.sh` ⇒ the repo-key file `~/.claude/autonomy/dod/repo-86523465733a9afe.md` has 73 `## ` blocks, 57 of them with `· toplevel=`. For this cwd the lineage filter keeps **16 blocks, 0 attributable to this toplevel, 0 checkboxes at all** (newest kept header `## 2026-08-18T19:58:39Z (manual-set)`). The latest `Scope (frozen):` kept is another wave's telemetry contract from two months earlier. `_dod_filter_file` keeps unattributable blocks on purpose (`hooks/lib/dod-path.sh:171`: "unattributable (pre-provenance) — inherited, never dropped"). The research worktree shows the same: 16 kept / 0 boxes. |
| RESEARCH_* | none | No. `rp_resolve_cwd` for the incident cwd ⇒ empty. `programs.json` lists 1 program (truememory-2-0). Even with a program it is report-only (`:2497-2499`). `~/.claude/autonomy/research/decision-recheck-2026-10-18/` exists but was created after the incident (T:607) and is not registered. |
| GOAL | none | No. `grep -c '"goal_status"' T` ⇒ 0, and it is report-only. |

**How common is the vacuous `met`?** Estimated, not measured on live sessions. `/tmp/rpic-A-ledger/dodscan.py` simulates the view of a toplevel with no lineage ancestors over all 78 `~/.claude/autonomy/dod/*.md`: it keeps only unattributable blocks and the pre-header text. In **74/78** files that view holds zero checkboxes, and 68/78 keep at least one unattributable block. So almost any repo's fresh worktree with no DoD of its own reads `SCOPE=met`, not `unknown`.
- No test pins this. `tests/wrap-ledger-research.bats:103-111` covers "met" only with two `[x]` boxes, and `grep "printf.*Scope (frozen)" tests/wrap-ledger*.bats` finds only fixtures that carry boxes.

**The operator-readout surfaces in the incident.** T:465 shows the Stop systemMessage header as `OPERATOR ▸ 3 runnable now, 253 need your call · ✅ live on trunk`. That is the `else` branch at `operator-readout.sh:1355`, so SAFE TO CLOSE was **withheld**.
- The cause was `CERT_WROTE≠0`: the turn's only write was under `/tmp`, which is outside the cwd, and `session_wrote_here_this_turn` returns 1 (`hooks/lib/session-writes.sh:355-372`). It was not the scope check.
- The header still said "✅ live on trunk", and its `◆ 73 decisions — your call` line was buried as row 3 of the standing pile.
- `completion-assert.sh` **timed out** on that Stop (T:467: `hook_cancelled … durationMs 5337, timeoutMs 5000`), so no close-contract arm evaluated the final close.

**Also answering the brief's sub-question.** Yes: SCOPE=unknown with no DoD keeps RUNG=✅. Its READOUT starts "✅ Clean & landed — completeness UNKNOWN…" (`:2631`; sandbox S3 below). Only the certificate abstains on it (`operator-readout.sh:1353`, `:2148`).

## 4. Sandbox reproduction

The script `/tmp/rpic-A-ledger/sandbox.sh` mirrors the `setup()` at `tests/wrap-ledger.bats:10-79`: bare origin, a clone, landed `main`, gate-green on HEAD, every store fixtured into the temp dir, `WRAP_CACHE=off`.
- It uses the **real** `bin/cc-decide` (`list` only) against `CC_DECISIONS_DIR=$T/decisions`.
- Packets are hand-written JSON: 5 open class-C packets with `session_sid=f1274fba-…` and conviction 80 plus a receipt.
- `WRAP_SESSION_ID=74728043-…`.
- `cc-decide list --open --class C --json | jq length` ⇒ 5, so the store is readable.

| Case | RUNG | READOUT | Key fields |
|---|---|---|---|
| S1 5 foreign packets, DoD `- [x] item one` | ✅ | `✅ Complete & live on trunk — nothing to do.` | BLOCKED=0 BLOCKED_SRC=WRAP_SESSION_ID SCOPE=met UNCONVICTED_MINE=0 |
| **S2 5 foreign packets, DoD = one `## … (manual-set)` + `Scope (frozen): …` block, ZERO boxes (incident shape)** | **✅** | **`✅ Complete & live on trunk — nothing to do.`** | **DOD=present REMAINDER=0 SCOPE=met** BLOCKED=0 |
| S3 5 foreign packets, DoD absent | ✅ | `✅ Clean & landed — completeness UNKNOWN: no durable DoD to confirm scope (…)` | SCOPE=unknown |
| S4 no session id | ✅ | `✅ Complete & live on trunk — nothing to do.` | BLOCKED_SRC=none |
| S5 control: + 1 packet of MINE, no conviction | 🔧 | `🔧 Loose ends — 1 item(s) you filed … no stated conviction …` | UNCONVICTED_MINE=1 |
| S6 control: + 1 packet of MINE, conviction 70 + receipt | ⛔ | `⛔ Blocked — need your call: fixture decision bbbbbbbbbbb2.` | BLOCKED=1 |

Command: `bash /tmp/rpic-A-ledger/sandbox.sh`. S5 and S6 prove the fixture can fire, so the 0 in S1-S2 is a real negative. In all cases `LIVE_SRC=unknown` (no live repo fixtured) and `CUSTODY_SRC=cwd` with a count of 0. Neither changes the arm reached.

## 5. Where a "research done — implementation pending" state would go

### 5a. The missing input (a precondition for any ladder change)

The ladder never reads prose, and it must not start (`:6-8`: "LIVE git/gate/DoD facts ONLY"). Today no store records that "session S produced a recommendation for X that has not been implemented yet". Two minimal producer shapes would supply it. Both are inferred designs; neither is built.

- **P1. A re-check stamp on the decision packet**, e.g. `.rechecks[] = {sid, ts, recommendation, conviction, receipt, disposition: signoff|agent}`, written by a new read-mostly cc-decide verb. The ledger's `$mine` at `:1500` becomes `(.session_sid==$sid) or ((.rechecks//[])|any(.sid==$sid))`.
  - This is a one-line jq change. It keeps the alarm-polarity guard: only packets **this** session re-checked count, not the 58-packet pile. In the incident it would have read `⛔ Blocked — 56 decision(s) need your call` instead of ✅.
  - Limit: ⛔'s sentence says "Blocked". It does not say "research complete — implementation pending", so the readout text at `:2508-2510` needs a recheck variant.
- **P2. A session-scoped "pending implementation" record** of research whose output is not a packet, e.g. a needs-human-shaped row carrying conviction and receipt, or a research receipt with `implementation_pending`. Counted like YOURS/FILED_MINE with `.sid==$SID` and fail-open (`none`/`error`/`skip`, as at `:1299-1305`).

### 5b. The ladder arm

- **Primary insertion point: a new `elif` between `:2626` and `:2627`.** It sits after the 👤 arm and before `[ "$DOD" = "absent" ]`. Here it fires only on a ✅-eligible tree, and costs nothing on 🔧/📦 closes, which is the same cost discipline as `:2524-2529`. Rung choice:
  - **Sign-off needed** (the operator's checkpoint): RUNG=**👤** with a new sentence, e.g. `👤 Research done — N implementation(s) await your sign-off; on yes I recycle into implementation (handoff-fire --recycle).` Merge it with the YOURS arm rather than outrank it: both are "the operator's queue", and 👤's existing text "My side is done & landed" is false while an implementation is pending. Using 👤 keeps the D7 act-line contract (`completion-assert.sh:1610`, 👤 only), which forces the one command onto its own line.
  - **Reversible, non-breaking, low-stakes** (the agent should just do it): this belongs in the **🔧 band at `:2563-2574`**, beside FILED_MINE and UNCONVICTED. Its precedent is CLOSE_FLOOR, a scope-keyed floor that says "you were sent to do X and have not" (`:1452-1481`). Sentence: `🔧 Loose ends — research done, implementation is yours and reversible: implement it now.` Do not place it below 👤: a drivable loose end outranks an operator queue, the same reason FILED_MINE outranks 👤 (`:2564-2565`).
- **Do NOT add a new glyph.** `operator-readout.sh:1236-1250` names the trap: an unhandled rung leaves `state` empty. There are 11 RUNG-comparison sites outside the ledger (`grep 'case "$RUNG"\|"$RUNG" = '` over hooks/scripts/bin), 35 files reference `wrap-ledger.sh`, and the 2026-10-01 ruling already refused a glyph for the scope variant (`:2629`).
- **Separate fix: make the vacuous SCOPE abstain.** At `:936-940`, set `SCOPE=unknown` when the filtered stream has **zero boxes** (checked + unchecked = 0) or **no block attributable to this toplevel**.
  - Effect: the incident's line 2 would read "completeness UNKNOWN" (row 13) instead of the default row 15.
  - Done alone, this does not express "implementation pending". It does stop the false "Complete … nothing to do" and keeps SAFE TO CLOSE withheld for every no-DoD research worktree. Per the estimate above, 74/78 DoD files are exposed.

### 5c. How the new state interacts with each rung and with the certificate

| Rung | Interaction |
|---|---|
| ⛔ | Outranks it. With P1, re-checked decisions *become* ⛔, so the new state is reached only when nothing of mine is undecided. |
| 🔧 dirty / remainder | Outranks it. The tree is already not done, and the arm is never computed there. |
| 📦 | Outranks it. Unlanded value is worse than unstarted value. The arm is never computed (the `else` branch at :2523). |
| 🔧 custody / resident | Outranks it. In-flight work must return first. Note: if the implementation is recycled via handoff-fire, custody 🔧 takes over naturally (`:2530-2543`). |
| 🔧 filed / unconvicted / floor | Same band as the "agent" disposition. Order it after UNCONVICTED (an un-researched ask is a worse loose end than a researched one) and beside CLOSE_FLOOR. |
| 🔧 no-trunk / 🚀 | Outrank the 👤 ("signoff") disposition, as they already outrank YOURS (`:2575-2617`). |
| 👤 | The "signoff" disposition is a 👤 sub-case. With both present, use one sentence naming both counts. |
| ✅ variants (DoD-absent, converging) | Rank below it. Pending research must win the single line over "completeness UNKNOWN". |
| **✅ SAFE TO CLOSE** | Any non-✅ RUNG mechanically withholds both certificate surfaces: the header (`operator-readout.sh:1351` lives inside the `"✅")` case, `:1339`) and the standalone one (`:2113 [ "$RUNG" = "✅" ] || abstain`, re-confirmed at `:2138`). No certificate edit is needed if the state is a 🔧 or 👤 sub-case. If it were instead kept at RUNG=✅ (the SCOPE precedent), it would need a new field, a new abstain token next to `cert-scope-unknown` (`:2148`), and a new branch at `:1351-1355`. That is three edit sites in place of zero, which argues against it. |
| close-shape template | Unchanged under 🔧. Under 👤 the D7 act line already applies. The line-1 template (`close-shape.sh:179`) still needs a third verdict example, e.g. `❌ Good to close: no — research done; implementation awaits your sign-off`. Otherwise the model will keep reaching for "yes — nothing of mine is open". |
