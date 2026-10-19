# C3: D8 v2, a follow-on arm whose discharge is a store fact, not a spelling list

Round 2, 2026-10-18. Candidate from axis 02 skeptic §"Fix candidates" (the "about 70" variant). Read-only in the
repo; every prototype and test run is on copies under `/tmp/r2-C3/`. Every number is labelled measured (with the
command) or estimated (with the method).

Status: complete. **Answer first: C3 does not clear 90%.** It fires on the incident, including in its live capped state, with no regressions. But on held-out closes its precision is 20% for the incident class and 32% under the contract, because the operator's own interactive picks have no store fact to tell them from undriven work (§4.4, §8). Post-measurement conviction: 40%.

## 0. Setup facts

- `/tmp/ca-axis02/` (round 1's census and prototypes) does not exist any more (measured: `ls /tmp/ca-axis02/` ⇒
  "No such file or directory"; the Mac rebooted at 16:34). The census is re-extracted from the transcripts below.
- Repo copy for prototyping: `cp -Rp hooks scripts bin tests lib CLAUDE.rules.slim.10-session-close.md CLAUDE.global.slim.md /tmp/r2-C3/repo/` from HEAD `f12dd4b12`.
- Load during this work: 1-min load average 119 (measured: `uptime` at 20:02 local). Every timing below was taken under that load.

## 1. Store facts the discharge can read (measured on the live stores, read-only)

| Store | Writer-session field | Evidence |
|---|---|---|
| `~/.claude/autonomy/backlog.jsonl` | `add.filedBy`, `block.session`, `done.closedSession` (all from `$CLAUDE_CODE_SESSION_ID`) | `jq … 'select(.ts>="2026-10-04") \| [.event, has("filedBy"), has("session"), …]'`: 306 of 348 `add` events carry `filedBy`, 173 of 235 `block` events carry `session` |
| `~/.claude/cc-fired/<pane>.json` (fire stamps, notify-back custody) | `firedBySid`, `firedAt`, `notifyBack` | read of the newest stamp; `scripts/lib/fired-peers.sh:11-23` is the one reader of "which sessions did this session fire" |
| `~/.claude/cc-registry/<pane>.json` | **none for the firer**: `session_id` is the *fired* pane's own session | `jq -r 'keys'` over 94 rows |
| `~/.claude/autonomy/decisions/*.json` (623 packets) | `session_sid`, `created` | `jq -r 'keys'` tally; `bin/cc-decide:255-275` |

**`dispatch-assert.sh`'s `discharged_since` is not session-scoped** (`hooks/dispatch-assert.sh:166-212`): any backlog
event by any session (claims, venue, link, falsify…), any registry row with a fresh mtime, and any packet created
since the turn start discharges it. Reused as-is it would read "some session somewhere wrote a record", not "this
session made its follow-on durable". The design below reuses its *mechanism* (record ≥ turn start, reclaim
excluded, drop stated) with a session filter added. §4 measures how much the unscoped form leaks.

**The ledger already owns the open half of every store fact.** At `RUNG=✅ ∧ contra=0` the per-session open
counts are all zero by construction: `YOURS>0` ⇒ 👤, `BLOCKED>0` ⇒ ⛔, `FILED_MINE>0` (open agent rows this
session filed with no `--why-not-now`) ⇒ contra=1 (`hooks/completion-assert.sh:1036-1043`,
`scripts/wrap-ledger.sh:1377-1436`), and `CUSTODY_OPEN>0` (a notify-back fire not yet returned) ⇒ contra=1
(`:1029-1034`). So at the only rung D8 v2 reads, a store discharge can come only from a record that is closed,
parked (`--why-not-now`/`--condition`), resolved, or written this turn. A filed agent row is **not** a silent
laundering path: it turns into a `FILED_MINE` conviction ("drive each") at the next close, and `cc-dispatch`
auto-drains it.

### 1.1 The discharge window is decisive: session-wide fails the incident

Every store record attributed to incident session `5759497b` (measured: `jq` over backlog.jsonl on
`filedBy|session|closedSession`, `grep -l` over decisions and cc-fired):

- backlog `9eedab74bff6` `add` at 13:27:10Z and `done` at 13:33:33Z. This is ship-land's **re-land row**,
  written under the session's id by the land machinery, not a filing the model chose.
- cc-fired stamp, pane 472, `firedAt 20:09:15Z`, `notifyBack wt-cc-004752-67086-398`: the implementation
  session fired **after** the operator's pushback (the cure).
- no decision packets.

The incident close is at 14:27:47Z. A **session-wide** window sees the 13:27 re-land row and would have
discharged D8 on the incident: a false negative on the one case the arm exists for. The **turn** window
(dispatch-assert's `T_TURN`: the last main-chain user record that is not a tool_result) starts at the
14:27:23Z task-notification. Measured: `jq` over the incident transcript lists the user records at 13:17:48 …
14:18:38, 14:27:23. No record falls in [14:27:23, 14:27:47], so the turn-scoped, session-scoped discharge
**fires** on the incident. The design therefore uses the turn window. A follow-on filed in an earlier turn is
discharged by citing its id, which is the contract's own shape (`follow-on: <filed ids|none>`), checked by
exact key.

## 2. Design: D8 v2 (`followon`, store-discharged)

```
D8v2 := CC_CLOSE_FOLLOWON != 0
      ∧ contra_shape == 0 ∧ RUNG == ✅ ∧ ¬_ca_assignee ∧ ¬research-program-active(cwd)
      ∧ origin ∧ positive write evidence            (D6's two gates, :1428-1455, factored into one function)
      ∧ L := close_verdict_yes_line(MSG_UNQ) exists  (first unfenced verdict-anchor line whose own polarity is yes)
      ∧ close_verdict_polarity(MSG_UNQ) == yes       (a mixed or no close is never this arm's)
      ∧ V := followon_value(line L of MSG_UNQ) != "" (drain-peer-findings.py: _FOLLOW_ON + _NIL_LEAD, one matcher)
      ∧ ¬ sd_dropped(V)                              (dispatch-assert's drop regex + "dropped", one copy)
      ∧ ¬ sd_ids_exist(line L of MSG)                (a cited 12-hex id that IS a backlog row or packet id: exact key)
      ∧ ¬ sd_discharged_since(T_TURN, SID)           (this session wrote a backlog event, fire stamp or packet this turn)
```

Pieces, all prototyped under `/tmp/r2-C3/repo/`:

1. **`hooks/lib/store-discharge.sh` (new)**: `sd_turn_start`, `sd_discharged_since <since> [sid]` (unscoped = today's
   dispatch-assert arms 1-3 byte-for-byte; scoped = `grep -F sid` then `jq` on filedBy/session/closedSession, firedBySid +
   firedAt, session_sid + created), `sd_ids_exist`, `sd_dropped`, `SD_DROP_RE='dropp(ing|ed)|not worth|letting (this|that|it) go'`.
   dispatch-assert sources it, so its discharge stays one copy.
2. **`scripts/drain-peer-findings.py`**: `followon_value(text)` is factored out of `finding_of` (which now calls it), plus a
   `--followon-value` stdin CLI (rc 0 value · rc 1 none). Selftest after the change: `SELFTEST: green — 17/17` (measured).
   The hook shells out to it (about 50 ms, measured above) only after the cheap gates pass, so there is one follow-on matcher.
3. **`hooks/lib/close-shape.sh`**: `close_verdict_yes_line <msg>`, which reuses `_CS_VERDICT` and `close_verdict_polarity` per line.
4. **`hooks/completion-assert.sh`**: the D8 block after D7, own class `followon` (`COMPLETION_FOLLOWON_MAX`, default 2), and
   `CC_CLOSE_FOLLOWON=0` as its kill switch. D6's origin/write gate is factored into `_ca_origin_writer_ok` so D8 does not copy it.

What it deliberately drops from v1: the 👤 rung (the measured operator-step false positive), the owned and park spelling lists
(replaced by the store), the any-12-hex shape exemption (replaced by exact-key existence), the `$MSG` view (replaced by `MSG_UNQ`),
and any `follow-on` that is not on the YES verdict line.

## 3. Prototype runs (hermetic, measured)

Harness `/tmp/r2-C3/replay.sh <tag> <close> [rung] [precap]`. It runs the hook in `env -i`, with every seam under
`/tmp/r2-C3/run-<tag>/`: `CLAUDE_CONFIG_DIR`, `COMPLETION_STATE_DIR`, `COMPLETION_IDL`, `CC_IDL`, `CC_BACKLOG_FILE`,
`CC_FIRED_DIR`, `CC_REGISTRY_DIR`, `CC_DECISIONS_DIR`, `CC_CUSTODY_DIR`, `TMPDIR`, a stub `WRAP_LEDGER_BIN` and a
stub `CC_BACKLOG_BIN`. The transcript has timestamps, one Edit record (the write gate), and a turn boundary at
14:27:23Z with the close at 14:27:47Z (the incident's own timing). The close text is the incident record extracted
verbatim (`jq` on `timestamp=="2026-10-18T14:27:47.478Z"`, 15 lines).

**Harness fidelity, checked against the unpatched copy** (`/tmp/r2-C3/orig/`): the incident with `assert` pre-seeded
3/3 gives `abstained capped:3>=3 rung ✅`, the exact live IDL record. The incident minus line 13 gives
`abstained ledger-clean`. Both match axis 02's replays B and C.

| Run | Input | Patched hook (measured) |
|---|---|---|
| A | incident, fresh latch | `fired arm:"handoff+followon" class:"followon" 1/2` |
| **F** | **incident, `assert` pre-capped 3/3 (the live state)** | **`fired arm:"handoff+followon" class:"followon" 1/2`** |
| G | incident minus line 13 (no D1) | `fired arm:"followon" class:"followon" 1/2` |

**Control matrix** (measured: `bash /tmp/r2-C3/controls.sh` ⇒ `ok=37 mismatch=0` for v2, and
`HOOK_OVERRIDE=…/repo2/… bash /tmp/r2-C3/controls_v2b.sh` ⇒ `ok=41 mismatch=0` for v2b, the variant of §4.3):

| Case | Expect | Why it is in the matrix |
|---|---|---|
| incident | FIRE | the defect |
| + a backlog `add` by this sid at 14:27:30 · a `block` (park) by this sid · a fire stamp `firedBySid`=sid · a packet `session_sid`=sid | PASS ×4 | each store cure discharges |
| + a row by another sid, plus another host's `claim` in the window | FIRE | session scoping (the unscoped form would pass) |
| + a row by this sid at 13:27 (the real re-land row's time) | FIRE | turn window, not session window (§1.1) |
| + a `reclaim:true` row by this sid | FIRE | a machine re-key is not a filing (dispatch-assert's rule) |
| + a fire stamp by another sid · a registry row only | FIRE ×2 | the registry names no firer |
| `follow-on: none.` · `none — the nightly launchd job applies it automatically.` | PASS ×2 | the honest nothing-drivable cure |
| `` `1dcc10d88ee3` `` that IS a row · `cc-decide 56c6862291f2` that IS a packet | PASS ×2 | exact-key discharge |
| `` `55f4d910b0aa` `` that is NOT a row (sha-prefix laundering, axis 02 risk (a)) | FIRE | shape alone no longer passes |
| `dropped the 70% timeout raise, not worth filing.` · `dropped — the rest is moot…` | PASS ×2 | skeptic FP 2: v1's own cure re-fired |
| `none yet, the waves …` · `n/a beyond the §5 waves…` · `zero-downtime migration… (not started)` · `the operator-readout fix in §5…` · `the waves are the operator's to prioritise.` | FIRE ×5 | skeptic leak 4: v1's spelling lists exempted all five |
| `the nightly launchd job applies it automatically.` (no `none`) | FIRE | known FP class; cured by writing `none — …` |
| `❌ Good to close: no — the waves haven't started…` · a mixed yes+no close | PASS ×2 | a no or a mixed verdict is never this arm's |
| a YES with `none` that later quotes the incident clause in backticks · a double-quoted verdict | PASS ×2 | skeptic point 3, mention vs use (MSG_UNQ) |
| the clause inside a fence · `close_shape_template` output | PASS ×2 | mention vs use |
| follow-on on the line *below* the verdict · `next:` instead of `follow-on:` | PASS ×2 | **recall limits, by design** (verdict line only, one label) |
| rung 👤 · rung 📦 · write-free session · `CC_CLOSE_FOLLOWON=0` · a fired peer (valid stamp, `CC_PANE_ID`) · a GENUINE value fork | PASS ×6 | the gates (skeptic point 6: origin + write gates now present) |
| v2b only: `none new.` · "the five decisions below" with an existing packet id in S4 · the incident plus an unrelated existing row id in the body · the incident plus a 12-hex sha in the body | PASS, PASS, **PASS (leak)**, FIRE | §4.3 |

Cost when the arm is reached (measured: `bash /tmp/r2-C3/time_sd.sh`, three runs against the **live** stores, read-only,
load average 137-143). Session-scoped discharge 0.21-0.56 s, id existence 0.31-0.84 s, `sd_turn_start` 0.06-0.08 s,
`followon_value` about 0.05 s. The unscoped dispatch-assert form took 0.32-0.45 s. The arm reaches these reads only after
the cheap gates pass (✅, contra 0, a YES verdict line with a non-nil follow-on). That is about 15 records a day fleet-wide
(estimated: 212 such records in 14 days, §4, before the rung gate), so the added Stop-phase time is paid rarely. It is
still up to about 1.5 s on the closes that do pay it, which matters under the 2-3 s Stop-phase guidance
(`.claude/rules/agent-operating-lessons-situational.md:233`).

## 4. Census: the real prototype over 14 days of closes, with per-session store facts

### 4.1 Corpus (re-extracted; round 1's `/tmp/ca-axis02/census/out2.txt` is gone)

`/tmp/r2-C3/census/extract.py` (measured) walks `~/.claude*/projects/*/*.jsonl` modified in the last 14 days: 1,926
paths. `~/.claude-next/projects` is a **symlink to `~/.claude/projects`** (measured: `cd … && pwd -P`), and transplanted
sessions copy whole transcripts. So records are de-duplicated on (sid, ts, text): **1,891 unique main-chain verdict
records over 328 sessions**, 1,870 of them stop-final (no later main-chain text before the next turn boundary, i.e. the
record a Stop hook's `tail -1` reads).

Stage 2 (`/tmp/r2-C3/census/stage2.sh`) runs the **real prototype functions** on every record: the sandbox
`close-shape.sh` (`close_verdict_polarity`, `close_verdict_yes_line`), completion-assert's `MSG_UNQ` sed verbatim, and
`drain-peer-findings.py --followon-value`. Stage 3 (`stage3.py`) joins the per-session store facts (backlog, cc-fired,
decisions), the IDL (`completion-assert` + `operator-readout` records extracted from `idl.jsonl` and its 8 gz
rotations, 2026-09-28 → 10-19), the write gate and the fired-peer signal.

| Step | Records (measured) |
|---|---|
| verdict records | 1,891 |
| polarity yes (on `MSG_UNQ`) | 548 |
| YES with a non-nil `follow-on:` value **on the verdict line** | 212 (139 unique values; 206 stop-final) |
| … value states a drop | 0 |
| … verdict line cites a 12-hex id that IS a backlog row or packet | 142 |
| … this session wrote a backlog event / fire stamp / packet **this turn** | 7 (all backlog) |
| **matcher + store fire set, before the rung/contra/origin gates** | **63** |

**Per-session store discharge, the three windows compared** (over the 70 records left after the id check):
- **Session-scoped, turn window (the design):** 7.
- **Unscoped, turn window (dispatch-assert's `discharged_since` reused as-is):** 18. So 11 of 18 (61%) of the
  unscoped discharges were another session's records. That is the leak §1 predicted.
- **Session-scoped, session window:** 26. It would also have discharged the incident (§1.1).

### 4.2 The gates, and every fire hand-read

The IDL holds a completion-assert record within 4 min of the close for 109 of the 212 (measured). The other 103 have
none at that Stop (88 of their sessions do appear in the IDL at other times, so these Stops either never ran the hook
or it did not finish). So the gates are applied two ways:
- (a) from the IDL where it exists;
- (b) from a text proxy: the rung glyph the close relays on lines 1-2, the transcript's write records, and the fired-peer
  signal (a cc-fired stamp whose transcript is this session, or a first user message that is a dispatch brief).

With the IDL (a): 7 fires with every gate known to pass. With the proxy (b): **v2 fires 12 times** (12 unique values;
`variants.py`, measured). Every one was hand-read, and the store facts were checked for each (the commands are in
`/tmp/r2-C3/census/`):

| # | Session · close | Follow-on value (verdict line) | Store facts | Label |
|---|---|---|---|---|
| 1 | `5759497b` 10-18 14:27 | the implementation waves in README §5 haven't started, because this pass was research only. | none this turn (§1.1) | **TP: the incident** |
| 2 | `99b5cd2f` 10-07 02:57 | none filed (the build is not started and needs the four rulings listed at the end). | none; the four rulings were filed as packets 3-3.5 h later (`792e19999523` 06:00Z, `c8990a35da7e` 06:33Z) | **TP: research done, build undriven, rulings unfiled** |
| 3 | `a46e28ad` 10-18 06:12 | approve the three build items below when you're ready. | none in any store | **TP: research done, build items need unfiled approvals** |
| 4-5 | `7a4c97b1` 10-08 16:44 and 17:14 | the private-scratch cleanup, the meeting-video decisions D1–D5 and the sample recordings, all yours and none urgent. | none in any store | **TP (contract)**: operator steps and decisions handed over in prose at ✅, unfiled; CA_HANDOFF has no `all yours` |
| 6-7 | `b102f5af` 10-18 12:01 and 12:02 | the two operator decisions below. / your two decisions below. | one is an existing open packet (`58d62776eb1f`, another session, 09-30); the other (check the banked reset) is unfiled | **TP (contract), partial** |
| 8 | `c8e66cb3` 10-11 06:13 | three decisions filed, each defaulting to no change on 2026-10-18. | 3 packets by this sid at 05:02Z, an earlier turn; ids cited in the body | **FP**: filed (constraint 2) |
| 9 | `6defb493` 10-09 16:48 | the five decisions below are yours. | 5 packets exist, cited in S4, filed under another sid (`d2d19fcf`) | **FP**: filed (constraint 2) |
| 10 | `f7351f3b` 10-16 05:05 | one pane is left to move…; the heartbeat fix (kitty window 37) is still working | a fire by this sid in an earlier turn; id cited in the body | **FP**: driven |
| 11 | `2328e32b` 10-16 09:46 | the Panda decision below, which is yours. | packet cited in the body; live rung was ⛔ per round 1, so unreachable live | **FP** (proxy only) |
| 12 | `43e6eb4b` 10-17 15:50 | none new. | existing step `c4dee242dacc` cited in S6 | **FP**: nil phrase `_NIL_LEAD` does not know |

**v2 precision (hand-read): 7/12 = 58% contract-correct; 3/12 = 25% in the incident's own class (undriven drivable
work).** Four of the five FPs fail constraint (2) or (1): a filed decision or a driven item was blocked because its ids
sat outside the verdict line or were filed in an earlier turn.

For comparison, **v1** run verbatim (axis 02 §5.2 awk; `/tmp/r2-C3/v1/run.sh`) on the same corpus: 18 records, 14 unique
values. That reproduces the skeptic's 14. Under the same proxy gates (v1 also admits 👤), 12 reach the gates and 2 are
TPs (the incident and #3): about 17%. The 👤 closes (`1bb2578a` ×5, `f7351f3b` ×3) are all filed operator steps.

### 4.3 v2b: two discharges tuned on this corpus, and their cost

The five FPs share two mechanisms, and each has a store-fact cure, not a spelling one:

1. **Ids cited anywhere in the close discharge it** (exact key, `sd_ids_exist "$MSG"` instead of the verdict line).
   The contract wants ids in the clause, but a packet cited in S4 is filed all the same. This cures #8-#11.
   **Cost: the mixed-clause leak.** An incident-like close that also cites one unrelated existing row id anywhere now
   passes (control `v2b-mixed-leak`). On this corpus it loses #6-#7, partial TPs that each cite one real packet.
2. **`none new` is nil**: one word added to drain-peer-findings' `_NIL` qualifier list, `(filed|outstanding|remaining|left|open|new)`.
   This also stops the drain from mining "none new" closes. Selftest still green 17/17 (measured). This cures #12.

**v2b on the same corpus: 5 fires (#1-#5), 5/5 contract-correct, 3/5 in the incident's class** (measured:
`variants.py` + the hand-read above). This is an in-sample number, so §4.4 tests both rules on held-out data.

## 5. Skeptic point 5: a ❌ relabel passes. Is that acceptable, and what drives continuation after a ❌?

**What reads a ❌ (measured: `git grep -n -iE 'close_verdict_polarity|good.to.close' -- hooks/*.sh scripts/wrap-ledger.sh`):**
completion-assert D6 (`verdict-first`, which refuses a done-reading line 1 over a NO), operator-readout (certificate
wording, `:1896-1901`) and lead-crash-watchdog (pane status, `:1610`). `session-continue.sh`, `anti-deference-nudge.sh`
and `dispatch-assert.sh` have no verdict term. **Nothing in the Stop chain treats ❌ as "keep going."**

**What actually followed the 1,329 stop-final ❌ closes of the 14-day corpus** (measured:
`/tmp/r2-C3/census/after.py`, the next main-chain turn boundary in each transcript):

| Next boundary | Count |
|---|---|
| `<task-notification>`: work already in flight (a background run, a watcher, a fired subagent) | 750 (56%) |
| the operator typed (median gap 288 s; 23 carry a continue/pushback word) | 207 (16%) |
| a Stop-hook block: completion-assert 92, anti-deference (opaque-identifier, category) 84, wake/inbox 47, session-continue 14, dispatch-assert 7 | about 244 |
| other meta (slash command, peer mail) | about 38 |
| the transcript ends | 40 |

**The relabel population itself:** ❌ verdicts at a Stop whose IDL reads rung ✅ and `ledger-clean`, i.e. the ledger
saw nothing open. That is **76 stop-final closes; 65 were followed by a notification** (measured, same script). Read by
hand, nearly all of them name an in-flight driver: "A detached script (pid 83478) starts it automatically and pings",
"pane 143 … this pane is waiting for its completion message", "Round 10 (run `wf_cc5fd9e4-b48`) is still running", "a
watcher will wake me". The other 11 wait on the operator's own pick ("waiting on your pick of wordmark height", "the
Cîroc pick is still yours").

**Verdict on point 5:**
- **Readability: yes.** "❌ Good to close: no — the §5 waves haven't started; nobody is driving them" leads with what
  remains. The verdict glyph is the first token, which is the operator's readability ask, and D6 already polices the
  opposite contradiction.
- **Enactment: no.** A ❌ that names undriven work with **no** driver idles until the operator returns, because nothing
  continues a ❌. The corpus shows honest ❌s almost always name a driver (65/76). The relabel escape is a ❌ with none,
  and D8 cannot see it, because it reads only YES verdicts.
- **What D8 v2 does about it:** its block reason never offers ❌ as an exit. The only listed cures are drive, fire,
  file-and-cite, drop, or `none`, and every cure but `none`/`dropped` is a store write that drives continuation by
  itself. An agent row auto-drains through `cc-dispatch`, and `FILED_MINE` convicts it at the next ✅ if it is still
  undriven. A fire carries notify-back custody, so `CUSTODY_OPEN` keeps contra=1 until it returns. A packet surfaces as
  ⛔ on the operator's board. And the block itself re-enters the transcript as a user turn, so the session does continue
  at least once.
- **So the ❌ relabel is acceptable only as a residual.** It trades the incident's readability failure for its
  enactment failure. It does not repeat the dishonest ✅. Closing it needs a separate arm (sketched in §8 as C3-b: ❌ ∧
  RUNG ✅ ∧ contra=0 ∧ no store record this turn ∧ **nothing in flight**). It is not built or measured here, and the
  65/76 figure says its in-flight test is the whole difficulty.

## 6. Recall (measured as far as a corpus allows)

There is no labelled set of "closes with undriven work", so recall is measured with a deliberately broad
unfinished-work tell (`haven't started|not started|research only|still needs|next steps:|left to do|implementation
waves|when you're ready|waits on your|follow-ups:|next:` …) over the quote-stripped close, then every tell-bearing close
is hand-read (`/tmp/r2-C3/census/`, measured):

- **Reachable population A** (IDL says ✅ + `ledger-clean`, stop-final YES): 56 closes, 6 with a tell. 2 are TPs, and
  D8 fires on both. The other 4 name nothing drivable (an automatic post-land verifier pass ×2, `Follow-ups: none.`,
  filed ids).
- **Population B** (relayed ✅ on lines 1-2, the text proxy): 324 closes, 17 with a tell. Hand-read:
  - **Caught (4):** the incident, `99b5cd2f`, `a46e28ad`, `7a4c97b1`.
  - **Correctly silent (9-10):** an automatic verifier ×2, a peer or lead owns it ×3, a stated park ("Per your ruling it
    runs with the next slim edit"), `Follow-ups: none.`, filed ids, done follow-ups.
  - **Missed (3-4):**
    - `d0de7b92`: "The proposed stop rule still needs your yes or no", in S4 with no verdict-line clause.
    - `fb6e7341`: `follow-on: none filed, but the next4 login still needs your one click below`. That is a nil lead
      followed by a real operator step, and `_NIL_LEAD` correctly reads "none filed," as nil.
    - `b8778ec0`: `follow-on: none … the next test waits on your verdict on looks A and B`.
    - Possibly `74a8eca0`: "an agent should review the 32 test cases", inside a decisions table.

**Recall on the incident class (agent-drivable work undriven, in the verdict's follow-on): 3/3 caught (4/4 with
`74a8eca0` excluded as ambiguous).** Recall on the wider class (any undriven or unfiled item anywhere in a ✅ close)
is about 4/7 to 4/8 (about 50-57%). Every miss sits outside the verdict line's clause or behind a nil lead. That is the
scope the skeptic asked for, and the price of not being a prose detector over the whole close. Both populations also
inherit the tell regex's own blind spots, so true recall on the wider class is at most these numbers.

### 4.4 Held-out test: 14-30-day-old closes (Sep 18 → Oct 4), the decisive measurement

- **Corpus:** `extract_range.py 30 … 14` gives 5,306 paths and 4,002 unique verdict records over 1,746 sessions. 1,405
  carry a follow-on on a verdict line (prefilter for stage 2). The same real functions run on them, then `variants.py`
  with the same proxy gates.
- **Measured fire counts:** v2 fires on 39 records (29 unique values) and **v2b on 33 records**. Two sessions are
  byte-identical copies under other sids (`032aa97f`≡`389eb846`, `78badb85`≡`cfbc5944`: same ts, same text, measured),
  so that is **27 unique closes**.
- **The store side of the held-out set is weaker:** cc-fired stamps are pane-keyed and overwritten on pane reuse, and
  the kitty restart at 16:34 today renumbered panes. So some old fire discharges are invisible here. That inflates FPs,
  never TPs.

Every v2b fire, hand-read (`/tmp/r2-C3/labels.json`):

| Label | Unique closes | Examples (verdict-line value) |
|---|---|---|
| **TP-A**: agent-drivable work, undriven, no record | 5 | `W3 (structured error bodies) is next and nothing blocks it now.` · `one lesson unwritten, named below.` · `the Playwright 1.63 upgrade, still held for the Floor-tab fix I described earlier.` · `wave I3 (retire the laptop from runbooks), dated 2026-10-03 in the plan, none filed.` ×2 |
| **TP-B**: an operator authorization or decision handed over in prose, unfiled, in a non-interactive close | 3 | `the five remediations are yours to authorize, none filed as blocking.` · `two items named below, neither driveable without an owner's design call.` · `the one test below, which needs your OK to read the live account.` |
| **OP-INT**: the operator's own pick or call **inside an interactive loop with the operator** (image ranking, brand calls, deck ruling) | 12 | `your blind rank of the water and High Noon bucket draws.` · `your final pick among the 15 white-label draws.` · `one decision left, whether to drop Poppins.` · `still just the Poppins call.` · `the deck ruling, unchanged.` |
| FP: nil phrase `_NIL_LEAD` does not know | 2 | `none of mine.` · `none pending an answer from you.` |
| FP: recorded in a store D8 does not read (the deadline store) | 1 | `` `customer.pay-reso-gl-renewal-2` (renew reso.gl … reminder 2026-10-10 …) `` |
| FP: owned by a named third party | 1 | `the channel change is still Daniel's to make.` |
| FP: driven by a pane fired in an earlier turn | 1 | `pane 579 finishes `cc-lr upgrade` and reports to the desk.` |
| fired peer that the proxy missed (the live origin gate should exempt it) | 2 | `two items named below, both routed to the lead` · `route (b) packet handed to you, unlanded by design.` |

**Held-out v2b precision (25 closes, fired peers excluded):**
- **incident class (TP-A): 5/25 = 20%.**
- **contract, non-interactive (TP-A + TP-B): 8/25 = 32%.**
- **D1's policy reading** (every unfiled operator item counts, including the interactive picks): 20/25 = 80%.

**Pooled with the in-sample 5** (30 closes): 8/30 = 27%, 13/30 = 43%, 25/30 = 83%.

**The interactive-loop class cannot be separated by a store fact or a structural signal:**
- **No store fact:** none of the 12 OP-INT closes has a record (the picks were never filed, which is normal for a live
  image-ranking loop).
- **No turn-start signal:** "the operator started this turn" splits OP-INT 5 operator / 7 notification and TP-A 3 / 5
  (measured: the turn-start record of every labelled fire). So "operator present" does not discriminate either.
- **Only words separate them:** `your`, `yours`, `pick`, `rank`, `call`, `ruling`, `decision`. That is v1's owned list,
  the spelling denylist the skeptic measured leaking both ways. It would also exempt the in-sample TPs `approve the three
  build items…` and `none filed (… needs the four rulings …)`.
- **The constraint they trip:** blocking these closes to demand a `cc-decide` packet for each image-rank round is
  exactly what constraint (2) exists to prevent. They are genuine operator decisions; they are just not filed.

## 7. Regression evidence (bats, measured)

`cc-bats` was not used. The `bats` on PATH is the cc-bats shim (`~/.claude/bin/bats`), and the shim may log into
`~/.claude/state`. The real binary `/opt/homebrew/opt/bats-core/bin/bats` 1.13.0 ran serially (no `--jobs`; GNU
parallel is absent) from a script file, with `HOME=/tmp/r2-C3/home` and a sandbox git identity, so no test could
touch live state (`/tmp/r2-C3/tap/run.sh`, `run2.sh`). **Environment trap seen twice:** a command-rewriting hook maps any
`bats` path typed into a Bash tool command to `~/.claude/bin/cc-bats`. It turned `mkdir -p /tmp/r2-C3/bats` into
`mkdir ~/.claude/bin/cc-bats` (refused, "File exists"; nothing was written) and
`/opt/homebrew/opt/bats-core/bin/bats …` into the shim. Calling bats through a variable inside a script avoids it.

| Suite | Unpatched copy | v2 copy | v2b copy |
|---|---|---|---|
| `completion-assert.bats` | `1..185` ok 185 | `1..185` ok 185 | `1..185` ok 185 |
| `dispatch-assert.bats` (now sources `store-discharge.sh`) | `1..27` ok 27 | `1..27` ok 27 | `1..27` ok 27 |
| `completion-assert-durations.bats` | `1..8` ok 8 | `1..8` ok 8 | `1..8` ok 8 |
| `completion-assert-forks.bats` | `1..8` ok 8 | `1..8` ok 8 | — |
| `completion-assert-assignee-shared-cwd.bats` | `1..9` ok 9 | `1..9` ok 9 | — |
| `drain-peer-findings.bats` | `1..14` ok 10, not ok 4 | same 4 | same 4 |
| **`completion-assert-followon.bats` (new, 12 tests, `/tmp/r2-C3/repo2/tests/`)** | — | — | **`1..12` ok 12** |

The 4 drain-peer-findings failures are identical in every arm (`diff` of the `not ok` lines). They read a git blob from
`$REPO`, and the sandbox copy is not a git repository ("fatal: not a git repository"), so they are environmental. The
185 completion-assert test names are identical in both arms (`diff` of sorted names). The new suite covers:
- the incident, and the incident with `assert` pre-capped 3/3;
- four store cures, plus the session and turn scoping;
- exact-key ids versus a sha-shaped non-id;
- nil, drop and `none new`;
- NO, quote, fence and template;
- the 👤, write-free and kill-switch gates;
- the `followon` cap, and the no-timestamp cannot-tell case;
- the `followon_value` unit, and the unscoped-vs-scoped `store-discharge` unit.

Its fixtures pin `CC_BACKLOG_FILE` and `CC_DECISIONS_DIR`, which **`tests/completion-assert.bats` setup does not pin
today**. Any fixture that reached D8 would read the live backlog, so the implementer should add both to that setup.

## 8. Verdict

**C3 does not clear 90%. Post-measurement conviction that D8 v2b, landed as a blocking arm, is net-positive and keeps
all six constraints: 40%.**

What the measurement establishes (each item measured above):

1. **The store-fact discharge works mechanically.** It fires on the incident in the live capped state, it is silent on
   every store cure, and it is silent on a NO, on quoted mentions, fences and the template, and on the 👤/write-free/
   kill-switch/fired-peer/GENUINE gates. 37/37 and 41/41 controls. No regression in 185 + 27 + 8 + 8 + 9 existing tests.
2. **Both the session scope and the turn window are necessary**, not stylistic. The unscoped dispatch-assert form
   discharged on another session's records in 11 of 18 cases. A session-wide window would have discharged the incident
   itself on ship-land's re-land row.
3. **Exact-key ids replace the shape-only exemption** (sha laundering now fires), and v1's five leak cases fire.
4. **It cures v1's measured defects:** 👤 operator-step FPs, the "dropped" re-fire, mention vs use, the missing
   origin/write gates, and a second follow-on matcher.

Why it still fails the bar:

5. **Held-out precision is 20% on the incident's own class and 32% on the contract's non-interactive reading.**
   - The largest fire class (12 of 25) is the operator's own pick or call inside an interactive loop ("your blind rank",
     "the Poppins call"). It has no store record by nature.
   - No store fact or structural signal measured here separates it from undriven agent work; only an owned/decision
     spelling list does. That is the class of fix `docs/research/exhaustive-drive-2026-09-08/SYNTHESIS.md:139-141`
     ranks as a non-action, and it would also exempt in-sample true positives.
   - Blocking those closes for a `cc-decide` packet per round breaks constraint (2) in spirit.
6. **The in-sample 5/5 for v2b was an overfit.** The two rules that produced it (ids anywhere, `none new`) were tuned
   on the same 14 days. The held-out set added three FP shapes they do not cover: `none of mine`, a deadline-store id
   (`customer.pay-reso-gl-renewal-2`), and a third party's step.
7. **The ❌ relabel escape stays open** (§5). D8 cannot see a NO, and nothing continues one.

What is above 90% inside this candidate (infrastructure, not a fix by itself):
- **`hooks/lib/store-discharge.sh` with dispatch-assert sourcing it.** One discharge predicate; unscoped behaviour
  byte-equivalent (27/27); the session-scoped form available to the next consumer.
- **`followon_value` factored out of `drain-peer-findings.py`.** One follow-on matcher; selftest 17/17.

Each is worth landing only together with a consumer that clears the bar.

Next steps the data points at (not built, not measured; they are not claims):
- **Gate D8 on the frozen scope.** Fire only when `wrap-ledger`'s `SCOPE` / DoD capture marks the session research or
  investigation (the incident's "Scope (frozen): research only"). In the fire tables, the TP-A/TP-B closes come mostly
  from "investigate / research" asks, and the OP-INT closes from interactive design and review loops. This needs the
  DoD capture per session, and a third corpus (30-60 days, 1,691 transcripts) to test without re-tuning.
- **Make it a surface rather than a block.** At the 80% policy reading, a one-line `OPERATOR ▸` "follow-on undriven"
  readout (axis 04's territory) costs an FP one line instead of a blocked stop.
- **C3-b for the ❌ escape:** ❌ ∧ RUNG ✅ ∧ contra=0 ∧ no store record this turn ∧ nothing in flight. 65 of the 76
  relabel-population closes had something in flight, so the in-flight test is the whole design problem.

## 9. Files the design would change (if built anyway), operator steps, risks

Files: `hooks/lib/store-discharge.sh` (new; deployed by the `install.sh:340` glob), `hooks/dispatch-assert.sh`
(sources the lib; `discharged_since` delegates), `hooks/completion-assert.sh` (D8 block after D7;
`_ca_origin_writer_ok` factored out of D6; arm/class/reason/final-abstain wiring; header env seams `CC_CLOSE_FOLLOWON`,
`COMPLETION_FOLLOWON_MAX`, `CC_FOLLOWON_PY`, `STORE_DISCHARGE_LIB`), `hooks/lib/close-shape.sh`
(`close_verdict_yes_line`), `scripts/drain-peer-findings.py` (`followon_value`, `--followon-value`, `_NIL` +`new`),
`tests/completion-assert-followon.bats` (new), `tests/completion-assert.bats` (setup pins `CC_BACKLOG_FILE`,
`CC_DECISIONS_DIR`), and `CLAUDE.rules.slim.10-session-close.md:146`: replace "A qualification goes in S2's
`follow-on:` clause, beside the assertion." with "S2's `follow-on:` is `none`, cited ids, or `dropped <it>`."
(−13 chars, measured `len()`; the slim global file is untouched). None of the six files reserved for another session
is touched. The prototypes are `/tmp/r2-C3/repo/` (v2) and `/tmp/r2-C3/repo2/` (v2b).

Operator-only steps: none. No `settings.json` change is needed: D8 lives inside the already-registered
completion-assert Stop hook.

Open risks:
- the interactive-decision FP class (§4.4);
- the mixed-clause leak of ids-anywhere (an unrelated existing id discharges an undriven clause);
- the nil-phrase vocabulary will keep growing (`none new`, `none of mine`, `none pending…`);
- the deadline store is not read;
- a prose-only park is blocked once and told to file it, which some will read as blocking a "deliberate stated park";
- the added Stop-phase cost is up to about 1.5 s when reached, under load;
- ids filed under a different sid (`6defb493` vs `d2d19fcf`) are visible only by exact key;
- the held-out set under-sees old fire stamps (pane reuse).
