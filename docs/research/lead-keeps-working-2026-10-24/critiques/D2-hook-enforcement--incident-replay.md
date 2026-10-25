# Critique: D2-hook-enforcement, through the incident-replay lens

Design: `designs/D2-hook-enforcement.md` (cited as `D2:n`). Lens: replay the B13 incident step by step against this
design. For each step: where the design breaks the idle, which mechanism does it, and whether that mechanism is
deterministic (a hook) or advisory (text the same model already ignored once). Also: would the lead still file
`290215743799`, and would it re-ask a ruling?

Abbreviations: `TX` = the B13 lead transcript (`~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`),
`TX:n` = jsonl line n. `IDL` = `~/.claude/autonomy/idl.jsonl`. `R` = `CLAUDE.rules.slim.10-session-close.md` (measured
byte-identical to `~/.claude/rules/10-session-close.md`, `diff -q`). `MAP` = `maps/incident-replay.md`,
`WAKE` = `maps/wake-path.md`. Code paths are in this worktree. Nothing was written except this file.

**Verdict: sound-with-fixes. Certainty of preventing a recurrence: 6/10.** The design deterministically refuses the
06:44:40Z idle (F1) with one block. Everything after that block is advisory. The lead can turn the block off for
good with one `dod-persist.sh set "Scope (held): e869fac7eb34 — …"`, and the ledger READOUT advertises that
command at every ⛔ close from 02:36Z onward. A stubborn lead is not blocked again at F2 or F3. In the exact B13 F3
state, the first supervisor wake is (estimated) swallowed by the detached watcher.

---

## 1. Answer in five lines

1. **Where it breaks the idle:** at the Stop after **F1 (06:44:40Z, `TX:4437`)**. The new `scope_floor` in
   `hooks/session-continue.sh` (`D2:442-497`) blocks once (1/2). It reads `RUNG=⛔ ∧ BLOCKED=2 ∧ SCOPE_UNGATED=1 ∧
   in-flight=0`, and `SCOPE_UNGATED` comes from the intake capture of `TX:14` on 2026-10-22. This is the first close
   that is both idle and has nothing in flight. Every earlier ⛔ close (02:36-05:02Z) correctly abstains
   `scope-floor-inflight`.
2. **Deterministic part:** the session cannot end F1 without one more forced model turn carrying an explicit
   instruction. All preconditions hold on the measured record (§3).
3. **Advisory part:** what that turn does. The block offers one work path and three state-change discharges
   (class-B re-file, `Scope (held)`, `Scope (done)`) (`D2:523-533`). Two of those (`held`, `done`) silence the
   floor and the supervisor for the rest of the decision state. A bare prose re-close is `scope-floor-latched` and
   allowed (`D2:487`).
4. **Filing (02:36Z):** the change that most likely prevents the class-C packets is advisory: the R:160 template.
   The lead copied today's R:160 template flag for flag (§5). With a class-B template it would most likely file
   class B. 290215743799 **would still be filed**. The design's claim that the grant prevents it is anachronistic
   (§5, defect D4).
5. **The "No round 27 until you answer" prose:** the floor ignores prose, so the prose does not disarm it. But the
   prose expresses exactly the belief that `Scope (held)` turns into a durable off-switch (defect D1).

---

## 2. Step-by-step replay

All counterfactual outcomes are **estimated** (reasoned from the design text and the cited code). The inputs are
**measured** where marked.

| # | Time (Z) | Event (evidence) | Design outcome | Mechanism | Det./Adv. |
|---|---|---|---|---|---|
| S0 | 10-22 07:41:31 | Recycle brief, the first genuine user record, `TX:14` (measured: records 1-13 are `last-prompt`/`mode`/attachments/snapshots) | The first Stop writes `## … (intake-first-prompt) · toplevel=/Users/chrisren/Development/agent-context-sync · session=666022fd…` plus the loop line, so `LOOP_OPEN=1` from here on | `scope_intake_capture` (`D2:363-393`) | **Det.** Measured: extraction returns the 790-byte `Scope (frozen): loop until dry. Each round = …` line. The anchored RE1/RE2 match it under `/usr/bin/awk` 20200816. All 3423 cwd-bearing records carry the same cwd (`jq .cwd \| uniq -c`). The line contains neither `backlog` nor `drain`, so DRAIN_SCOPE is unaffected (`scripts/wrap-ledger.sh:945`) |
| S1 | 02:22-02:25 | Operator messages (`TX:4114`, `TX:4163` queued). Lead: "I won't start round 27 until you've decided on the stop rule" (`TX:4199`), rung 🔧 from custody | Floor kind `loop` → `scope-floor-inflight` (custody open) | `scope_floor` in-flight test (`D2:473-475`) | Det. (allow, correct) |
| S2 | 02:36:16 / 02:36:27 | `cc-decide open --class C …` ×2 (`TX:4254`, `TX:4260`) | **Probably class B** under the new R:160 (`D2:778-780`). If class C anyway: a stderr route hint after the write (`D2:711-717`). The lead pipes `2>&1 \| tail -3` / `tail -2`, so a one-line hint stays visible (estimated) | Rule-text template plus a stderr hint | **Adv.** Strong advisory: the filed commands reproduce R:160's template order exactly (`--class C --what … --conviction … --receipt … --option … --option …`, R:160 vs `TX:4254`) |
| S3 | 02:36:34 | Lead writes "No round 27 until e869fac7eb34 is answered" to lead-notes, then reads its own READOUT (`TX:4270-4271`) | READOUT gains "Not gated by it: your loop scope … keep driving it … (stop only once `dod-persist.sh set "Scope (held): <id> — …"` records that it gates all that remains)" (`D2:264-268`) | Ledger text | **Adv.** It also **advertises the off-switch** at the moment the lead has just written the hold (D1) |
| S4 | 02:36:51-05:02:50 | ⛔ closes while round-26 lanes and then the land are in flight (`TX:4273`, `4294`, `4316`, `4334`, `4359`, `4420`) | `scope-floor-inflight` (CUSTODY_OPEN is now computed under ⛔ when ungated, `D2:258`; LANDING is computed unconditionally, `scripts/wrap-ledger.sh:859-872`, and the 05:02 land ran in the lead's own checkout, `TX:4415-4420`) | In-flight test | Det. (allow, correct: control C1) |
| **S5** | **06:44:40 (F1)** | Land done (`TX:4428-4431`), watcher re-armed (`TX:4434`), close "❌ Good to close: no … Nothing more runs until you answer" (`TX:4437`) | **BLOCK 1/2.** The reason names the loop, both ids with gloss, the class-B command, and held/done (`D2:517-534`). completion-assert `no-close-tell`, anti-deference `no-tell`, boundary-handoff declines (unchanged) | `scope_floor` | **Det. (the break point)** |
| S6 | F1+1 turn | The model answers the block | (a) runs round 27, in flight from then on; (b) re-files class B, so the key changes and the 🔧-loop kind blocks again 1/2; (c) `Scope (held)` or `Scope (done)`, so the floor and supervisor go silent; (d) re-closes in prose, `scope-floor-latched` | Model choice | **Adv.** |
| S7 | 07:39:47 (F2) | Watcher timeout wake, close (`TX:4458`) | Variant (d): same key, same HEAD ⇒ `scope-floor-latched`, allow (`D2:487`) | Latch | Det. (allow) |
| S8 | 08:34:49-08:34:59 (F3) | `cc-await-ping 134 --timeout 3300 … &` inside a background Bash (`TX:4469`), close "I'm stopping the inbox watcher" (`TX:4476`) | Variant (d): latched, allow. **MAP §7 F3 MUST "Block at F3" is not met** (D2) | Latch | Det. (allow) |
| S9 | 09:11:08 | First STALL? after F3 (measured: STALL? rows for this sid at 05:52:52-06:02:48Z, then none until 09:11:08Z) | `nudge_subject` sends. cc-notify very likely sees the orphan's live `<sid>.watching` ⇒ `delivered reason=wake-path-armed`, **no wake** (WAKE §4.1-4.3). enqueued=1 ⇒ marker written, attempt counted | Supervisor | Det. send, **no wake** (estimated; the orphan's survival is unverified, WAKE §4.3) (D3) |
| S10 | ~11:11, ~15:11 | Attempts 2 and 3 after the 2 h and 4 h back-off (`D2:662-663`) | Socket wake (no watcher after about 09:30Z), each carrying the instruction as mail. A stubborn re-close stays latched | Supervisor + cc-wake | Det. wake, adv. content |
| S11 | 18:11:47 | Operator message (`TX:4488`) | Compliant variant: the lead is mid-round. Stubborn variant: the same reply as today | n/a | n/a |

**Wall-clock effect, estimated:**
- **Compliant at S6:** the idle disappears (the design's 11 h 27 m, `D2:984`).
- **Fully stubborn:** idle is not shortened. The lead gets three instructions (F1, ~11:11, ~15:11), not four, and
  is silent after ~15:11.
- **Held/done at S3 or S6:** a full recurrence, now with a durable claim the operator's ⛔ block does not show.

---

## 3. Preconditions for the S5 block

Measured unless marked.

| Precondition | Status | Evidence |
|---|---|---|
| The loop scope is in the store under this sid | ✓ via S0 | See S0. Without S0 the store held only other sessions' blocks during the idle (`DOD:26-27` was written at 20:15:35Z, measured `sed -n 26p`) |
| SID resolves inside the hook's ledger call | ✓ | `_wl_resolve_sid` reads `CLAUDE_CODE_SESSION_ID` (`scripts/wrap-ledger.sh:506-512`). boundary-handoff's ledger read at F1 saw ⛔ (`IDL:3575` `freewin=⛔`), so BLOCKED=2 resolved in hook context |
| No custody, land, resident or live wave | ✓ | Custody all returned by 05:01:53Z (MAP §5). The land finished at 06:44:17Z (`TX:4428`). Tool uses: 484 Bash, 8 Workflow, **0 TeamCreate** (measured `jq … \| sort \| uniq -c`). The last wave finished around 02:36 (`TX:4260` copies `wf10qtkef.output`), outside the 1800 s warmth window (`hooks/boundary-handoff.sh:874-901`) |
| No kill phrase and no operator-hold phrase in the last user message | ✓ | Measured: `last_user_msg`'s exact jq filter (`hooks/session-continue.sh:420-427`) returns `TX:4114` at all three closes. KILL_RE (`:386`) and SCOPE_HOLD_RE (`D2:441`) both miss it (`/usr/bin/grep -iE`) |
| Not an assignee | ✓ | The only session-continue row for this sid is `ship-floor-budget` at 20:43:38Z ("count":2,"max":2). The ship floor got past its assignee check (`hooks/session-continue.sh:1189-1197`) |
| No research program | ✓ | `research-program.sh is-active` exits 1 on agentsync (`why-the-lead-idled.md`, authorization table) |
| No sentinel armed (the floors run only without one) | ✓ | No `session-continue.sh set` tool call in TX (measured grep: hits only at `TX:10/12/27`, rule-text attachments). Floors run under `if [ ! -f "$f" ]` (`hooks/session-continue.sh:1295`) |
| The hook finishes inside its 10 s timeout | ✓ (estimated) | Timeout 10 (measured `jq` on `~/.claude/settings.json`). At F1 the close is at 06:44:40.381Z and boundary-handoff's ledger-bearing row is at 06:44:42Z, so the ledger completed in about 2 s. The new forks (custody, `ps`, research, waves) run only on ungated ⛔ |
| **No `Scope (held)` written before F1** | ✗ **advisory** | The READOUT at `TX:4271` and `TX:4431` would print the held command (D1) |

---

## 4. Would it have filed 290215743799? Would it have re-asked a ruling?

**290215743799: yes, most likely, as class B.** The design's replay row says "with the grant in R, 290215743799 is
never filed" (`D2:981`). That cannot hold for B13. The grant's own `issued_at` is 2026-10-24T18:11:47Z
(`D2:928`), the operator message at `TX:4488`. The filing was at 02:36:27Z (`TX:4260`), almost 16 h earlier.

At 02:36 the only prior ruling was `a247b7288149`. The lead's research had found it and read it as TrueMemory-only:
"Consent for sending this repo to OpenAI or Google: no ruling found" (`TX:4235`). The new R:68 sentence asks the
lead to look for exactly what it already found, so it changes nothing here.

The lead also gave two reasons the grant text does not answer (`TX:4235`):
- "`codex exec -s read-only` can read any file on the machine … including the files the B13 rules forbid copying".
- "This repo's CLAUDE.md lists 'anything that names the tenant' as an escalation surface"
  (`agent-context-sync/CLAUDE.md:81-84`). The grant excludes "a repo-listed escalation surface" (`D2:862`) but gives
  no procedure for deciding whether an export hits one.

For a **future** incident the grant still leaves an ask. Even after the operator's grant, the auto-mode classifier
refused the Codex calls as `[Data Exfiltration]` (`TX` 18:16:50Z note and the 18:17:21Z denial, then 18:17:32Z "I
need one permission from you"). No `codex`/`xverify` string exists in `~/.claude/settings.json` (measured grep).
This change cannot add one (no settings edits). So the next lead that uses the grant hits a permission denial,
which is a legitimate class-C ask for that one act.

**e869 (stop the loop): it re-asks, and that is legitimate.** The lead knew the ruling it was asking to change: "On
October 10 you ruled 'build everything,' and the stop rule became 'keep going until a round finds nothing new'"
(`TX:4273`). It asked because the operator's own 02:22Z question was "is this forever?" (`TX:4114`). `eb3dbe1e5e94`
(class B, default "keep looping until dry (the scope as written)", expired-actioned 2026-10-15T15:06:34Z, measured
`jq`) never appears in TX (measured `grep -c` = 0). The optional P4 hint (`D2:718-722`) would surface it, but only
on stderr after the packet is already written, and the design refuses to block on it (`D2:1022`).

The failure was the class, not the re-ask. Precedent `eb3dbe1e5e94` was itself class B with a keep-looping default.
The R:160 change addresses the class. R:68 does not, and §5.2 overstates its part.

---

## 5. Defects

### D1 (major): the deterministic floor has a model-authored off-switch, and the ledger advertises it

`compute_held` (`D2:237-247`) sets `HELD=1` for any own `Scope (held):` line that names any open class-C id. It does
not check whether the packet has a status-quo course. With `HELD=1`:
- `SCOPE_UNGATED=0` (`D2:249`).
- The floor logs `scope-floor-nothing-ungated` and allows (`D2:460`).
- The supervisor's oracle drops the row (`D2:655-656` accepts only fired, latched, budget and shadow rows).

The result is a full B13 recurrence. The ⛔ readout is byte-identical to today's (`D2:271`, L2 test `D2:1045`), so
the operator sees no difference.

The B13 lead had already written this exact claim to a durable file: "No round 27 until e869fac7eb34 is answered"
(`TX:4270` → `~/.cache/agentsync-bring-back/b13/round26/lead-notes.md:9`). It also held an 85% conviction that the
loop should stop: "Is this forever? As set up, yes … I'm 85% for yes" (`TX:4273`, `TX:4294`). The design rejects
close prose as a discriminator because the model authors it (`D2:52`). It then adopts another model-authored line
as the discriminator.

The READOUT clause (`D2:267`) and `rung_next` (`D2:299`) show the held command at every ungated ⛔ close **without**
the criteria. The criteria (money, self-modification, permission, credential, a pick with no status quo) appear only
inside the floor's block text (`D2:529`). That text is never shown if the hold is written first.

**Fix:**
1. Drop the held command from the READOUT and `rung_next`. Show it only inside the floor block, with its criteria.
2. Honour `HELD` only for a packet that carries a gate category (graft D3's packet field). Failing that, refuse a
   hold on a LOOP scope unless the packet was filed class C after the new R:160.
3. Render a held ⛔ in operator-readout ("held by this session's claim: <id> gates all remaining work — <why>").
4. Let `nudge_subject` send one "re-confirm the hold" line when a held idle passes N hours.

### D2 (major): F2 and F3 are never blocked, against MAP §7's F3 MUST

The latch per `(key, HEAD)` (`D2:487`) lets every no-commit re-close through. MAP §7 says:
- F2: "If F1's block was spent (cap), this close must still be caught by a cap-reset rule … Otherwise the lead
  re-closes identically every 55 min."
- F3: "**Block at F3.** Failing that, the supervisor wakes the session itself within one ESCALATED cycle."

F3 is the last Stop before the 9 h 36 m gap. It is also the close that tears down the tracked wake path (`TX:4469`,
`TX:4476`). The design logs `scope-floor-latched` there and allows (`D2:985`).

**Fix:** re-arm the same key once at least 45 min have passed since its last fire, with the cap raised to 3. F1, F2
and F3 are then each blocked, and a stubborn session still costs at most 3 forced turns per decision state. A rapid
re-close still latches. As a cheaper alternative, fire once more when the close leaves no harness-tracked wake path
while ungated work remains.

### D3 (major): the replay's "~36 min" first wake is wrong for B13's own F3 state

`D2:986` says that at 09:05-09:11 "no live watcher ⇒ socket wake". The section it cites (WAKE §4.1) says the
no-watcher case applies to B13 only "from about 09:30Z, see 4.3". At 08:34:49Z the lead started a detached
`cc-await-ping 134 --timeout 3300 … &` (`TX:4469`; WAKE §4.3). If it survived, it stamps `<sid>.watching`:
- cc-notify then returns `delivered reason=wake-path-armed` and does not call cc-wake (WAKE §4.2).
- The orphan's exit wakes nobody.
- `nudge_subject` writes the `.nudged` marker anyway because `enqueued=1` (`D2:678-680`), so the attempt counts and
  the next one waits 2 h.

**Estimated** effective timeline: first wake about 11:11Z (about 2 h 36 m after F3, not 36 min), then about 15:11Z.
That is two delivered wakes, not three. `D2:1028-1029` concedes the hole; §5.2 then ignores it on exactly the state
that has it.

**Fix:**
- When cc-notify reports `reason=wake-path-armed`, do not write the marker.
- Re-check the subject's transcript at the next sweep. If it did not grow, resend once the watcher marker is stale
  (at most 3300 + 90 s), still inside the cap.
- Or adopt WAKE §4.3's fix: `hooks/validate-bash.sh` refuses `cc-await-ping … &`.

### D4 (major): the replay credits the grant and R:68 with preventing 290215743799. Both claims fail.

See §4. The grant is anachronistic for B13 (`D2:928` vs `TX:4260`). R:68 asks for a search the lead had already done
(`TX:4235`). For future incidents, the classifier denial (`TX` 18:17:21Z) and the missing allow rule still force a
permission ask.

**Fix:**
- Correct `D2:981`.
- Add to the grant text: "if the permission classifier refuses the call, keep the work running on the Claude-only
  path and file the allow rule as the one class-C act".
- Add a concrete escalation-surface check, for example grep the `git archive` export for the repo's listed terms
  before sending.
- Name the lead's "codex can read any file" concern. A read-only sandbox does not confine reads to the export.

### D5 (major): the 🔧-loop kind's in-flight test is blind on the DIRTY and REMAINDER 🔧 paths

The floor treats any `RUNG=🔧 ∧ LOOP_OPEN=1` as kind `loop` (`D2:456`), then reads `CUSTODY_OPEN` and
`RESIDENT_MINE` (`D2:467`). The ledger computes those two only on the ✅-eligible branch
(`scripts/wrap-ledger.sh:2622-2648`) and, new in D2, under ungated ⛔ (`D2:258`). On a 🔧 from DIRTY or REMAINDER
(`scripts/wrap-ledger.sh:2611-2614`) both read as skip ⇒ 0.

When `mechanical_arm` declines that dirt (attribution rc≠0, `hooks/session-continue.sh:1106-1110`), the scope floor
blocks with "nothing in flight … run the next round" while dispatched lanes are still open. That is a false block of
the C1 shape. For a sequential loop ("rehearse … on the landed tip", `TX:14`) it invites a duplicate or premature
round.

This arises in the class-B counterfactual the design itself prefers (BLOCKED=0 during 02:36-05:02Z), on any close
where the tree is dirty.

**Fix:** compute custody and residents whenever `LOOP_OPEN=1`, or have the floor abstain when
`CUSTODY_SRC=skip`. Add a test: 🔧-DIRTY + LOOP_OPEN + an open custody row ⇒ no block.

### D6 (minor): the compliance evidence is overstated

`D2:984` says the lead was "told the same thing at 18:12Z" (`TX:4495`). `TX:4488` never mentions the loop. It is an
operator rebuke about Codex autonomy. Machine block text carries less authority. The only Stop block the lead received
in the window (handoff-claim-assert, `TX:4274-4275`) was answered by fixing the complaint and restating "No round 27
starts until you answer the first question" (`TX:4294`). Compliance after S5 is an estimate with mixed evidence, and
the fallbacks (D2, D3) need to carry real weight.

### D7 (minor): SCOPE_HOLD_RE misses common operator holds, a false-block risk

Measured with `/usr/bin/grep -iE` on `D2:441`'s pattern:
- **Matches:** "wait for my answer before round 27", "don't start round 27 until I say", "hold everything until my go".
- **Misses:** "hold off until I decide", "Please hold until I reply", "pause the loop until I get back to you",
  "stop until I answer", "no more rounds until I decide", "wait on me".

Only the operator's **last** message is read, so an earlier hold followed by any other message is lost.

**Fix:** broaden the pattern (`until I|until my|until you hear`, `hold off`, `pause`). Also abstain while the
operator's last message postdates the open packet and contains "until I".

### D8 (minor): two token commits exhaust the per-decision-state budget

The cap of 2 per key (`D2:482`, `:488`), with re-arm only on a new HEAD, lets a reluctant lead discharge both blocks
by committing a round-27 brief twice and then idle for the rest of the decision's life.

B13's decisions were open about 16 h. A round takes about 7 h (round 26: dispatched 23:41-23:45Z on 10-23, landed
06:44Z, MAP §5 and `TX:4428`). The floor cannot tell a dispatched round from a token commit.

**Fix:** re-arm on a new in-flight dispatch (custody row or wave started since the last fire) rather than on HEAD
alone. Otherwise state the limit in §9.

### D9 (minor): the floor key has no sha1 fallback, so it fails silently off macOS

`D2:478` hashes with `${CC_SHA1:-/sbin/sha1sum}`, and an empty key returns 0 (`D2:479`), meaning the floor never
fires. The repo's other users carry `[ -x "$CC_SHA1" ] || CC_SHA1=sha1sum` (`hooks/accounts-board.sh:51`,
`hooks/plan-agent-teams-default.sh:86`). `/sbin/sha1sum` exists on this Mac (measured `ls`), but the suites also run
on GNU (`scripts/wrap-ledger.sh:965` notes "the suites run on both").

### D10 (minor): the intake capture still moves DOD_SCOPE for every session in the checkout

`DOD_SCOPE` is the newest frozen line of **any** session in the toplevel (`scripts/wrap-ledger.sh:913-928`). The
design refuses non-loop captures for exactly this crosstalk (`D2:112-115`). A loop capture has the same effect on
the ✅ certificate (`hooks/operator-readout.sh:532-545`) of every other session in agentsync's main checkout. That
checkout is shared: `DOD:9` is session `1f572e53`'s scope. The scope is narrower but not zero.

### Refuted concern, recorded for the final design

MAP §0.2 says dod-persist's PreCompact extractor "would capture a lane scope here". Measured otherwise:
`extract_scope` (`hooks/dod-persist.sh:141-147`) reads only `.type=="text"` blocks, and over `TX:1-4437` it finds
exactly 1 `Scope (frozen):` line, the loop line. The lane briefs (`TX:3875`, …) sit in tool_results. A PreCompact
would therefore have captured the right contract. The intake capture is needed only because this session never
compacted.

---

## 6. Ideas worth grafting into the final design

1. **The contract facts are session-scoped:** only `## … · session=<SID>` blocks count (`D2:56-62`), never the
   toplevel's DOD_SCOPE. This keeps alarm polarity, and the L4 test proves it (`D2:1047`).
2. **First-genuine-user-record intake, loop scopes only, marker written first** (`D2:363-393`). Measured to recover
   `TX:14`'s line, which closes the MAP §0.1 gap that would otherwise make any loop floor inert in B13.
3. **One anchored loop regex in a shared lib** (`D2:72-95`). Measured here to match the B13 line under macOS awk.
4. **A prose-blind floor in an already-registered hook** with these properties (`D2:442-503`):
   - keyed per decision state, latched per HEAD, capped;
   - fails closed on an unwritable state file;
   - writes an IDL row on every evaluation, which ends the "stood down vs never ran" ambiguity of today's
     `:1103`/`:1216`.
5. **Custody and residents computed under ⛔ only when ungated** (`D2:258`), plus the explicit rule that "an armed
   watcher alone is NOT in flight", with a mutant test (S7, `D2:1074`). F1 and F2 had a watcher and nothing else.
6. **A 🔧-loop arm inside the ✅-eligible branch** (`D2:283-286`), so a class-B re-file cannot turn the false ⛔ into
   a false ✅ (MAP §7 C5, test L6).
7. **A full class-B template in R:160** (`D2:778-780`). The lead reproduces R:160's template flag for flag
   (`TX:4254`), so this is the highest-yield advisory change.
8. **`nudge_subject` addressed to the subject by sid** (`D2:643-683`):
   - its oracle is the session's own floor row;
   - it is damped per decision state, fails closed, and never routes through the dead desk (`scripts/lead-supervisor.sh:414-415`);
   - it parses cc-notify's own `^cc-notify: verdict=` token and fixes `advise_subject`'s mis-parse (`D2:673-677`, `:700`).
9. **anti-deference files no prose-derived class-B packet under ⛔** (`D2:567-572`). This fixes the `f56cf0f827d7`
   junk packet.
10. **Fixtures built from MAP's verbatim closes**, plus one mutant per guard (`D2:1058-1084`).

---

## 7. Why 6/10

- The chain from intake to the F1 block is deterministic, and every input checks out on the record (§3). Estimated
  probability that the block is emitted: about 0.9. The main residual is an untested hook path under load.
- What the model does after the block is not controlled. Estimated:
  - compliance with "run the next round" or a class-B re-file: about 0.6-0.8;
  - a held/done escape: about 0.15-0.3;
  - a stubborn prose re-close: the rest.
  The method is judgment from the lead's stated hold and conviction (`TX:4270`, `TX:4273`, `TX:4294`) set against
  its quick switch under operator authority (`TX:4495`). No measurement exists for compliance with a scope-floor
  block, because no such block has ever fired.
- The fallbacks are weak exactly where B13 was:
  - no block at F2 or F3 (D2);
  - the first wake is likely swallowed (D3);
  - held/done silences everything (D1).

Fixing D1-D3 would move this lens to about 8. D1 cannot reach 10 without a non-model signal that says what a packet
gates.

---

## 8. What I ran

All read-only. Each check gives the command and its result.

**Transcript structure**
- `head -n 20 TX | jq -c '{t:.type,…}'`: the first user record is `TX:14`.
- `jq -r 'select(.cwd!=null)|.cwd' TX | sort | uniq -c`: 3423 records, one cwd.

**Intake capture and loop-scope match**
- The design's intake extraction on `TX:14`: 790-byte loop line, 0.039 s.
- `/usr/bin/awk` with RE1/RE2: `LOOP`.

**Last-user-message and phrase regexes**
- `last_user_msg`'s exact filter at lines 4437, 4458 and 4476, then KILL_RE and SCOPE_HOLD_RE through
  `/usr/bin/grep -iE`: no match. Nine hold phrasings tested separately.

**Session tool use and stall timing**
- Tool-use counts via `jq`: 0 TeamCreate.
- STALL? row times for the sid (`grep -F 666022fd IDL | grep STALL`).
- Sid-row count from 08:35 to 15:12 = 270, inside the oracle's `tail -n 400` window.

**Hook settings and IDL rows**
- `jq` on `~/.claude/settings.json` Stop timeouts: session-continue = 10.
- `grep 666022fd IDL | grep session-continue`: 1 row.

**Prior rulings and permissions**
- `jq` on `decisions/eb3dbe1e5e94.json` and `b4780d7bb60e.json`.
- `grep -c eb3dbe1e5e94 TX`: 0.
- `grep -i codex|xverify ~/.claude/settings.json`: none.

**Code paths read**
- `sed -n` on `hooks/session-continue.sh:320-460, 1018-1110, 1180-1345`.
- `scripts/wrap-ledger.sh:506-512, 835-880, 905-1000, 2585-2690`.
- `hooks/dod-persist.sh:1-30, 120-215, 460-510`.
- `scripts/lead-supervisor.sh:1040-1100`.
- `hooks/boundary-handoff.sh:860-910`.
- `hooks/lib/land-inflight.sh:33-37, 95-110`.

**PreCompact extractor replay**
- The extractor's jq over `TX:1-4437`: 1 frozen line.

My zsh tool shell aliases `grep` to ugrep, which rejects SCOPE_HOLD_RE ("exceeds complexity limits"), so every regex
replay above used `/usr/bin/grep`. That is the binary the hooks use under bash (measured `bash -c 'command -v grep'`).
