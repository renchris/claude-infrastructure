# Critique of D4-minimal-sufficient, incident-replay lens

Design: `designs/D4-minimal-sufficient.md` (cited as `D4 §n` or `D4:line`). Lens: replay the B13 incident step by step
against the design, say where and how the idle breaks, and say whether each mechanism is a hook (deterministic) or
text (advisory).

Read-only. The only file written is this one. Abbreviations follow the maps: `TX:n` is line n of the B13 transcript,
`IDL` is `~/.claude/autonomy/idl.jsonl`, `R` is `CLAUDE.rules.slim.10-session-close.md`. Every number is labelled
**measured** (with the command) or **estimated** (with the method).

Verdict: **sound-with-fixes**. Score on this lens: **6/10**.

---

## 0. Answers to the lens questions

1. **Where the idle breaks.** At F1, 06:44:40Z (`TX:4437`), K3 returns `decision:block`. That is the first close
   where custody is 0, no land is in flight and no workflow wave is live (D4 F7, F8). The block is deterministic.
   - It does not read prose, so "No round 27 until you answer" cannot suppress it. Its predicate reads only ledger
     fields, `cc-custody count` and live waves (D4:279-306).
   - Every input it needs was checked against the code (§6).
   - K1 would have captured the loop scope no later than the 02:36:51Z Stop. That Stop is ⛔, so `mechanical_arm`
     returns 1 at `hooks/session-continue.sh:1103`, `ship_floor` returns 0 at `:1217`, and `loop_floor` runs.
2. **The block is deterministic. What follows it is advisory.** The next turn runs round 27 only if the lead
   accepts the block's text.
   - The design's evidence for that is TX:4495 (D4:549). That was a reply to an *operator rebuke* (TX:4488), not to
     a hook.
   - This session's own history with hook blocks that contradicted a plan it had stated is poor (§2).
   - The block text also offers a one-line discharge that this lead's documented beliefs favour. Taking it silences
     K3 and K4 for good (defect 1).
3. **Would the lead have filed 290215743799?**
   - In the design's as-filed worst case: yes (TX:4260).
   - With D1 loaded at session start: probably not as a judgment packet. But the Codex call would then have hit the
     auto-mode classifier, which refused it as Data Exfiltration at 18:17:21Z (TX:4682-4683). That was six minutes
     after the operator's own chat authorization (TX:4488).
   - So D1 turns the packet into a permission ask, which is a legitimate class C. It does not turn it into a Codex
     review. D4 never mentions the classifier (defect 5).
4. **Would it have re-asked a ruling?** Yes, in both worlds.
   - C1's hint is inserted after the existing-packet return (`bin/cc-decide:313-328`). The new packet is still
     written (`:355`) and its id echoed (`:360`). C1 "never refuses" (D4:37).
   - So the hint arrives *after* the re-ask has already raised ⛔.
   - R:68's rewrite sends the pre-filing search to `cc-memory-search --all`, and `--all` adds memory stores, not
     decision packets (`bin/cc-memory-search:17`). So no pre-`open` search can find `eb3dbe1e5e94` (defect 6).
5. **A lead that also writes "No round 27 until you answer".**
   - The prose does not stop the first block.
   - It predicts the forced turn's answer. That lead either argues and closes, which `no-progress` then accepts
     (D4:320-322), or writes the hold line, which ends `LOOP_OPEN` and makes every later floor row `ungated:0`.
   - Estimated chance that round 27 starts before 18:11Z: about 0.6-0.7. That is a judgment from §2's compliance
     record, with the 2 blocks and 3 nudges treated as correlated tries, not independent ones.

---

## 1. Replay, as filed (the design's own worst case: class C, same prose, no rule followed)

| Step (Z) / TX | D4 mechanism | Kind | Result under D4 |
|---|---|---|---|
| 10-22 07:41 / TX:14, recycle brief | K1 at the first unarmed Stop. The extractor picks TX:14 alone (**measured**: D4's `jq` over `head -n 4476 TX` returns the loop line in 0.092 s wall, at load 147-206 by `uptime`). TX:14 is `type:user`, `origin.kind:"human"`, string content (**measured** `jq`). | hook | Captured. **Side effect:** 13 Stops in the next two days read ✅ (**measured**: operator-readout `rung` rows for 666022fd in `idl.jsonl.20261024T050411Z.gz`: ✅ 13, 🔧 93, 📦 69, ⛔ 6). K2 turns each into a loop 🔧, and K3 evaluates them under key (sid, `-`, head). See defect 2. |
| 02:22 / 02:23, TX:4114, TX:4163 | none | — | The operator asks "is this forever?". That is new operator input on the stop rule. |
| 02:25:42 / TX:4199, 🔧 with custody open | K3 abstains, `inflight` custody | hook | Correct. |
| 02:35:51 / TX:4235, research finds a247 | D1 (only if S was loaded at session start) | advisory | As filed: no effect. |
| 02:36:16 / TX:4254, e869 opened as class C | R:160 rewrite. C1 hint on stderr, *after* the decision to file | advisory | Packet written, ⛔. The hint says "LIKELY ALREADY RULED" too late to stop the filing. |
| 02:36:27 / TX:4260, 2902 opened | D1 | advisory | Filed. |
| 02:36:51 → 05:02:50, ⛔ closes | K3 abstains on custody (F7) or LANDING (estimated in D4) | hook | Correct (control C1). |
| **06:44:40 / TX:4437 (F1)** | **K3 FIRES 1/2** under key (sid, `290215743799,e869fac7eb34`, head). Hook time headroom is ample: session-continue took 1694 ms (**measured**, `TX:4440` hookInfos) against a 10 s timeout (**measured**, the Stop entry in `~/.claude/settings.json`). | **hook** | **Idle refused.** |
| F1′, the forced turn | The lead chooses (a) round 27, (b) the hold line from the block text, or (c) argue and close | advisory | (a) fixed. (b) the incident recurs in full and K4 is silenced. (c) see the next rows. |
| 07:39:47 / TX:4458 (F2), branch (c) | FIRE 2/2, *unless* F1′ ran any write. A `>>` lead-note append counts as a write in `turn_scan` (`hooks/lib/turn-scan.sh:65-66`), so the second block would fire inside the 06:44 burst. Re-arming `cc-await-ping` is read-only (`ro_word`, `:44`). | hook | Refused, or already spent. |
| 08:34:49 / TX:4469, watcher orphaned | none | — | — |
| 08:34:59 / TX:4476 (F3) | `loop-floor-budget`, `ungated:1` | hook | Allowed. |
| ~09:11, first STALL? after F3 (maps/wake-path.md §2.1) | K4 nudge 1. If the orphan watcher is alive, `wake-path-armed` (`bin/cc-notify:1501-1502`) means no socket wake. | hook | Not woken (estimated). |
| ≥11:11 | K4 nudge 2, socket wake (W3) | hook wake, advisory content | Woken. Branch (c) re-closes. |
| ≥15:11 | Nudge 3, then `subject_nudge_capped` | — | Branch (c): idle until 18:11Z. **The operator is never paged**, because `send_page` returns 1 with no desk (`scripts/lead-supervisor.sh:414-415`) and D4 §6 item 10 leaves that unfixed. |

So the design turns 9 h 36 m of *unbroken* idle into at most 5 interruptions. D4:556's "maximum idle falls … to
about 2.5 h" is **time to wake, not time to work**. In branches (b) and (c), no round runs before 18:11Z.

---

## 2. How this lead treats hook blocks (the evidence D4 needs and does not cite)

There are 16 `Stop hook feedback` records in TX (**measured**, `grep -n -a 'Stop hook feedback'`).

| Block | Did it match the lead's own plan? | What the lead did next |
|---|---|---|
| Ship floor, TX:659 and TX:736 | yes (it meant to land) | complied 2/2 (TX:660, TX:737) |
| Free-win recycle, TX:2326, 3197, 3948 | no | argued and did not recycle, 0/3 (TX:2327-2330, TX:3198-3199, TX:3949-3950) |
| Handoff-claim, TX:4274 | no | conceded the narrow point and **kept the hold** (TX:4280, TX:4294: "No round 27 starts until you answer the first question") |

At TX:4282 (02:37:08Z) the lead read `cc-decide`'s header: "C HARD-BLOCK (human-only) — C10 self-mod / C6 money-path
/ permission denial" (**measured** `grep` on that tool_result). Nine seconds later it re-closed with the judgment
call still held as class C (TX:4294).

Its lead note says "No round 27 until e869fac7eb34 is answered" (TX:4270), and its conviction for *stopping* was 85
(`DEC/e869fac7eb34`).

The loop floor contradicts a plan the lead wrote down. On this record, a contradicting block was complied with 0 of
4 times. Free-win was explicitly advisory and K3 cites an operator ruling, so K3 should do better, but nobody has
measured it. **Estimated** compliance with the first block: about 0.5.

One correction to the brief's framing: the idle was mostly *rule-following*. The 02:36Z commands copy R:160's
class-C template field for field (`R:160` against `TX:4254`). So R1's R:160 rewrite, which D4 calls
non-proof-critical (D4:36), replaces the exact text this model obeyed. It is likely the highest-leverage
*advisory* edit.

---

## 3. Defects

1. **Major: the block text supplies a self-certified discharge that silences K3 and K4.**
   - Evidence:
     - `lf_reason` (D4:347-349) and the K4 text (D4:399) both offer `dod-persist.sh set "Scope (frozen): hold until
       <decision id> is answered — …"`.
     - K2 then reads `LOOP_OPEN=0` (D4:190). Every later floor row is `loop-floor-no-loop ungated:0`, and K4 never
       nudges `ungated:0` (D4:395).
     - Nothing checks the claim. This lead already wrote the hold in prose (TX:4270) and kept a judgment call as
       class C after reading the reserved set (TX:4282 → TX:4294).
     - The hold also outlives the answer. After e869 is answered, the hold line is still the newest own Scope line,
       so the loop never re-opens.
   - Fix:
     - Make the discharge refutable from the packet. Refuse it, keeping `ungated:1`, when the named id is not an open
       class-C packet, or when one of its options restates the frozen course. e869's "no" option is "keep running
       rounds until one confirms nothing new" (`DEC/e869fac7eb34 .options[1]`), and `DOD:27` repeats that wording.
     - Expire a `hold until <id>` line when `<id>` is no longer open, so the previous own loop line governs again.
     - Leave the recipe out of the block text (keep it in G).
     - Route a hold written inside a floor-forced turn to the operator channel, not to silence.
2. **Major: the budget key ignores class-B packets, so in the goal-(b) world it becomes a lifetime budget.**
   - Evidence:
     - The key is cksum(sid | BLOCKED_IDS | head) (D4:308). BLOCKED_IDS lists only counted class-C packets
       (D4:199).
     - B13 had 13 ✅ Stops on 10-22/23 (**measured**, see §1). Each becomes a loop 🔧 with custody 0. TX:2326 shows
       one: a fire script running as a background Bash job, which the floor cannot see (TX:2327-2330).
     - The first two such Stops spend key (sid, `-`, head). In D4's own "rules followed" path and its control C5, the
       lead files class B, the ids stay `-`, and K3 logs `loop-floor-budget` at F1. D4:573's "the floor fires" holds
       only with a fresh latch.
     - This contradicts D4:267: "Budget per decision state, never per lifetime".
   - Fix: put every open packet this session filed (class B and C) into the key, or reset the key on an
     in-flight → idle transition (custody or wave count falling to 0). Add a bats case: spend the `-` key, file a
     class-B packet, assert a fire.
3. **Major: the loop 🔧 is inserted above 🚀, re-check ⛔ and 👤, not only above ✅.**
   - Evidence:
     - D4 places `elif LOOP_OPEN` right after CLOSE_FLOOR (`scripts/wrap-ledger.sh:2670`), before `-z TRUNK`
       (`:2674`). The chain then continues: LIVE_BREACH 🚀 (`:2685`), BLOCKED_RECHECKED ⛔ (`:2717`), YOURS 👤
       (`:2726`), ✅ (`:2735+`) (**measured** `awk` over the if/elif structure).
     - So a loop session masks the ship floor's 🚀 arm (`hooks/session-continue.sh:1217`), completion-assert's 🚀
       term (`:1166`) and its 👤 CLOSE_ACT arm (`:1643`). That contradicts D4:46 ("only where ✅ would otherwise be
       computed") and breaks the hard rule "never weaken an existing gate".
     - Even at the ✅ position, completion-assert's D6 close-shape arm is gated to `RUNG ∈ {✅,👤}` (`:1535`). It
       blocked B13 twice on 10-23 (TX:1929, TX:2974) and goes silent for every loop session.
   - Fix: insert the arm after `:2734`, just before the ✅ arms. Let D6 accept `RUNG=🔧 ∧ LOOP_OPEN=1`, or emit a
     `RUNG_BASE` field for it to read.
4. **Major: the claimed outcome is time-to-wake, and the operator stays unreachable.**
   - Evidence:
     - D4:556 counts a K4 socket wake as ending the idle.
     - In branches (b) and (c) of §1, nothing runs. After `subject_nudge_capped` nobody is told: `send_page` returns
       1 before cc-notify (`scripts/lead-supervisor.sh:414-415`; maps/wake-path.md §2.2), and D4 §6 item 10 leaves
       it unrepaired.
   - Fix: at `subject_nudge_capped`, or at any `loop-floor-budget ungated:1` row older than one back-off, call the
     existing liveness-free channel (`digest_add`, `:456-460`) with the ids and the loop head. Report "interrupted"
     and "worked" separately.
5. **Major (goal d): the grant cannot make cross-vendor review happen.**
   - Evidence:
     - The auto-mode classifier refused `xverify.py` as `[Data Exfiltration]` at 18:17:21Z (TX:4682-4683), after the
       operator's explicit chat authorization (TX:4488). The lead then asked for an allow rule (TX:4683).
     - D4's grant names `codex exec -s read-only` (D4:442), while the tool actually used was `xverify.py`.
     - D4 never mentions the classifier (**measured** `grep -n -i classifier` on D4 finds only `gate-classify.sh`).
     - An allow rule needs a settings edit, which is forbidden here.
   - Fix: say plainly that the grant records consent and does not clear the classifier. Name the operator step (the
     allow rule) as a filed 👤 item, and make the grant name the actual wrapper.
6. **Minor: C1 runs after the decision to file, and the R:68 search target is wrong.**
   - Evidence:
     - The hint goes at `bin/cc-decide:329`, but the packet is written at `:355` and the id echoed at `:360`.
     - R:68's rewrite names `cc-memory-search --all`, which adds memory topics, not packets (`bin/cc-memory-search:17`).
     - `eb3dbe1e5e94`'s default fired unattended (`DEC/eb3dbe1e5e94`: `expired-actioned`), and the operator's
       02:22Z message (TX:4114) reopened the question. So "LIKELY ALREADY RULED" overstates it. The right re-ask
       carries that default as class B.
   - Fix: R:68 names `cc-memory-search --decisions <terms>` *before* `open`. Change the hint wording to "a prior
     answer exists (default fired): re-ask only as class B with it as --default".
7. **Minor: the K4 rotation fallback reads the hash-chain archive.**
   - Evidence: `ls -t "$IDL".*.gz | head -1` (D4:391) returns `idl.jsonl.chain.20261024T050411Z.gz`. It is 8.6 s
     newer (**measured** `stat`: 1792818272.02 against 1792818263.40) and holds `n<TAB>sha256` lines (**measured**
     `gzip -dc | head`). So the F10 guard never finds a row.
   - Fix: glob `idl.jsonl.2*.gz`.
8. **Minor: K4 applies back-off before it compares keys.**
   - Evidence: D4:388 returns before D4:396 resets `c0` on a new key. A new decision state inside the window waits up
     to 4 h.
   - Fix: read the row and reset on key change first, then apply back-off.
9. **Minor: the class-B discharge in the block text leaves the class-C original open.**
   - Evidence: D4:350-351 says "re-file it as class B" and omits closing e869. BLOCKED stays 2. The 18:31Z re-file
     needed a separate `actioned` with evidence (`DEC/e869fac7eb34 .evidence`).
   - Fix: name `cc-decide action <id> --evidence "re-filed as class B <new id>"` in the text.
10. **Minor: the latch file is per cwd, not per session.**
    - Evidence:
      - `${f}.loop` (D4:310) sits on the continue sentinel, keyed on (config dir, cwd)
        (`hooks/lib/continue-sentinel.sh:29-33`).
      - Two idle loop sessions in one cwd overwrite each other's key, so `pc` resets to 0. The no-progress test runs
        only when `pc ≥ 1` (D4:320), so each Stop fires again and the bound is lost.
      - K1 now captures human-origin loop scopes for every session, which enlarges the population.
    - Fix: name the latch by sid (`${f}.loop.<sid>`).
11. **Minor: the timeout risk is misstated.**
    - Evidence: D4:781 cites a 5 s timeout. The registered value is 10 s, and the measured runs at F1-F3 took
      1694, 1268 and 2098 ms (`TX:4440`, `TX:4461`, `TX:4485`).
    - Fix: correct the risk line. The real budget risk is turn_scan's 4 MiB `jq` pass at load ~200.

---

## 4. Verified as the design states

- **K1 never re-captures its own text.** Stop hook feedback records are `isMeta:true` (`TX:4274`, **measured**), so
  `lf_reason`'s `Scope (frozen): hold …` cannot be re-captured as human scope. The cc-wake frame is
  `isMeta:true, origin.kind:"peer"` (`TX:5067`).
- **The ledger knows the session id in the Stop-hook shape.** boundary-handoff's own call returned `freewin=⛔` at
  F1-F3 (maps/incident-replay.md §6.1), and it runs with no `--session` flag (`hooks/boundary-handoff.sh:651`).
  So K2's own-line test has a SID.
- **No abstain path is hit at F1.**
  - Teardown: the B13 marker is from `2026-10-23T15:56:09Z`, about 14 h 48 m old at F1, outside the 1800 s window
    (**measured** `stat`; `hooks/session-continue.sh:599-616`).
  - Research program: the only registered program is `truememory-2-0` (**measured**
    `jq . ~/.claude/autonomy/research/programs.json`).
- **The floor order holds.** At F1 nothing earlier emits: `mechanical_arm` returns 1 on ⛔ (`:1103`) and
  `ship_floor` returns 0 off 📦/🚀 (`:1217`). completion-assert yields on any `${f}.blocked` arm name (`:1293-1297`).
- **The oracle row shape matches what `log_idl` writes.** It emits compact `"sid":"…","reason":"…"`
  (`hooks/session-continue.sh:85-95`), so K4's `grep -F` matches. The live IDL grep took 0.087 s (**measured**).

---

## 5. Best ideas to graft into the final design

1. **K1: capture at Stop from human-origin prompts only.** It fixes the real gap, which is *when* capture runs, not
   *what* it extracts (D4 F3). It is cheap and cannot re-capture its own hook text.
2. **K3's predicate.** It reads ledger state only, never prose or packet class, and keeps ⛔ first. It is the only
   mechanism in any design that fires at F1 *regardless* of "No round 27 until you answer". The live-wave exemption
   (F8) prevents the C2 false block.
3. **A budget per decision state**, so new packets re-arm it. Graft it with defect 2's fix: include class-B ids, or
   reset on in-flight → idle.
4. **The ⛔ READOUT loop clause and the `rung_next` change.** The lead greps `^READOUT` immediately before closing
   (TX:4430), so the clause lands at the moment of decision. That is the best-placed advisory text in the design.
5. **K4's direct `cc-notify <sid>` to the subject.** It bypasses the dead desk, keys on the session's own
   `ungated:1` floor row, keeps a marker that survives `clear_page`, and uses back-off. Add the operator-digest
   fallback (defect 4).
6. **The R:160 class-B template.** This model copies command templates verbatim (TX:4254 against R:160).
7. **C1's output ordering.** The ruling line goes last, before the id, so it survives `2>&1 | tail -3`. Pair it with
   a pre-`open` `--decisions` search.
8. **`codex-meter.sh`, fail-closed.** It turns the 80% stop into tracked code.

---

## 6. Score rationale (estimated)

- P(K3 blocks at F1 | built as specified): about 0.9. This is a judgment: the residual risks are a LANDING, custody
  or wave misread and a hook kill. The timeout headroom is measured.
- P(round 27 before 18:11Z | as filed): about 0.6-0.7, from §2's record, with 2 blocks and 3 correlated wakes.
- P(full recurrence through the hold discharge): about 0.2-0.3. In that branch K4 is silenced and the operator is
  not paged.
- With defects 1-4 fixed (a refutable discharge, a class-B-aware key, the rung placed only over ✅, an operator
  fallback): about 0.85.
