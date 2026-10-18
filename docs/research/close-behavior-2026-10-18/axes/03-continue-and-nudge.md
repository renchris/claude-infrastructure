# Axis 03: session-continue.sh and anti-deference-nudge.sh vs the 2026-10-18 close incident

Scope: `hooks/session-continue.sh` (1547 lines), `hooks/anti-deference-nudge.sh` (641 lines), and the
suites `tests/session-continue.bats` (61 tests), `tests/session-continue-forks.bats` (5),
`tests/session-continue-telemetry.bats` (12), `tests/anti-deference-nudge.bats` (61),
`tests/jev-anti-deference-arm.bats` (9). This was a read-only study. The only repo file written is this one.
Scratch fixtures and scripts are under `/tmp/ax03/` (outside the repo).

## 0. Answer first

None of the three incident shapes could fire either hook. The reason is structural, not a missing synonym.

- **anti-deference-nudge.sh treats deference as a question or a hold addressed to the operator.** Its
  15 `TELLS` are all of that kind ("say the word", "want me to", "should I proceed", "awaiting your").
  The incident replies were *declarative*: a recommendation register ("What I'd do, in order: 1. 2. 3."),
  a named-but-unapplied fix ("I didn't change anything. The fix is … I'm about 70% sure"), and an ownerless
  follow-on clause inside a YES verdict ("Follow-on: the implementation waves … haven't started").
  None of these asks anything. Run verbatim against all four messages, the hook's regexes matched **zero**
  tells, done-tells, category-tells, opaque ids, pane asks or peer deferrals (measured, §3). The IDL
  shows `abstained no-tell` at every one of those Stops (§2).
- **The semantic arm built for exactly this shape is retired.** Jev's question text (`:396`) reads
  "reports having IDENTIFIED remaining work without doing it". It is off by default
  (`CC_JEV_RETIRED:-1`, `:370`). The repo's own rule admits the gap: "a research turn that identifies
  ten items trips no arm and closes clean" (`CLAUDE.global.md:721`, also quoted at hook `:333-335`).
- **session-continue.sh reads git and mailbox state, never what the message says.** Its mechanical
  arm needs rung 🔧 plus this session's own dirty paths (`:1103`, `:1108`). Its ship floor needs 📦 or 🚀
  (`:1216`). Its wake floor is about inbox reachability (`:664-975`). Its agent-armed sentinel exists
  only if the agent runs `set`, and the rule steers away from that on a research turn: "Read-only /
  advisory / research … No ledger, no auto-continue" (`CLAUDE.rules.slim.10-session-close.md:34`,
  `CLAUDE.global.md:601`) and "On 🔧, and only on 🔧, arm" (`rules:217`). The plan turns were read-only,
  and the final close was ✅ landed. So every floor took a silent path.

**Fixes proposed (§6), each measured on 902 unique Stop-final main-agent messages from 542 transcripts
over 4 days:**

- **F1, `followon-undriven` arm.** It fires on 1 of 49 YES closes that carry a follow-on clause: the
  incident. It enforces the existing contract `follow-on: <filed ids|none>` (`CLAUDE.global.md:560`).
- **F2, `plan-not-driven` arm.** It fires on 2 of 902 messages, both incident turns.
- **F3, `diagnosed-not-applied` arm.** It fires on 2 of 902 messages: the 70% turn, plus one
  team-assignee message that the existing assignee carve-out already silences.

All three are additive arms in anti-deference-nudge.sh, under its existing latch, cap, assignee,
genuine-blocker and research-program carve-outs. Rule text gets a net cut.

## 1. Arm map

### 1.1 session-continue.sh

| Arm | Predicate (fires when …) | Bound | Silent / abstain paths | Evidence |
|---|---|---|---|---|
| CLI `set` / `clear` / `status` | Agent arms with `set "<step>"` (stamps `.sid`, `.cwd`, resets `.count`). `clear` removes it and **spends the mechanical budget** (`.mech` = `CC_MECH_MAX:-3`). `--if-mine` refuses a foreign or anonymous sentinel. | n/a | n/a | `:141-158`, `:159-293`, `:263` |
| Kill-switch | The last genuine operator message matches `KILL_RE` ("and stop", "no auto-continue", "just do X", "stop here", "come back to this", bare stop/halt). It skips isMeta and machine envelopes. | n/a | Clears the sentinel and allows the stop. | `:386-443`, `:1337-1342` |
| **Mechanical 🔧** (no sentinel) | Ledger `RUNG=🔧` ∧ `session_dirty_mine` lists ≥1 dirty path this session wrote. It arms the sentinel and falls into the armed path. | `.mech` per sid, `CC_MECH_MAX:-2`; product with `CLAUDE_CONTINUE_MAX` | Kill-switch, assignee rc0/2, teardown, no lib, rung ≠ 🔧 (silent), attribution rc≠0 (silent) | `:1018-1167`; rung gate `:1103`; attribution `:1108-1110` |
| **Ship floor** (no sentinel) | Ledger `RUNG ∈ {📦,🚀}` ∧ (📦: `session_unlanded_mine`; 🚀: `session_writes_paths`) | Once per HEAD sha; `CC_SHIP_FLOOR_MAX:-2` per sid | Kill-switch, assignee, teardown, not-mine (logged), latched (logged), budget (logged) | `:1186-1287`; rung gate `:1216` |
| **Wake floor** (no sentinel; also after a skipped re-block) | Not armed (`mailbox_wake_armed`) ∧ (first idle ∨ mail pending ∨ own custody open). Blocks with the `cc-await-ping` arm command. | `CC_WAKE_FLOOR_MAX:-2`, TTL 600 s | Mechanical async arm registered (logged), headless, live /goal + pending, assignee/teardown, kill-switch, budget | `:664-975`; trigger `:883` |
| Agent-armed continuation | A sentinel file exists ∧ sid matches ∧ count < `CLAUDE_CONTINUE_MAX:-8`. Blocks with `continue_reason` and folds peer mail. | Cap `:1445-1458`; a fresh `set` zeroes it | Kill-switch, sid mismatch, identical re-block after an idle forced turn (`reblock_is_idle_repeat`, `:1400-1442`) | `:1334-1547` |
| Idle detection | Only one kind exists: "about to go idle **without a wake path**" (wake floor), and "the forced turn made no write tool call" (`turn_scan .w`, used only to *skip* a repeat block). **No arm detects "idle while drivable work was just named."** | n/a | n/a | `:618-643`, `:1371-1387` |

Floor order on an unarmed Stop: mechanical → ship → wake, with at most one emitting (`:1289-1332`).

What the hook can see: sentinel files, wrap-ledger `RUNG/TRUNK/AHEAD/SHAS`, session-writes attribution,
mailbox and custody counts, and the last operator message (for the kill-switch only). It never reads
the assistant's message. The header says so by design: "keeps scope-judgment with the AGENT … this
script is a dumb actuator" (`:4-10`).

### 1.2 anti-deference-nudge.sh

Fire predicate (`:13-15`, chain `:524-561`): (tell ∨ (done ∧ ledger-contradiction) ∨ category ∨
opaque-id ∨ pane ∨ peer ∨ jev) ∧ ¬assignee ∧ ¬hard-genuine ∧ ¬(ship-hold ∧ ¬drivable). It reads only
the **last main-agent text** (`:159-163`).

| Arm | Exact list / shape | Line |
|---|---|---|
| `TELLS` (deference) | `say the word` · `say go` · `give me the word` · `on your word` · `want me to` · `shall i` · `should i (proceed\|do\|go)` · `let me know if you` · `holding for your` · `otherwise (i'll\|i will\|i'd) (hold\|wait\|leave\|hang\|pause\|stand)` · `your steer` · `do you want me to` · `awaiting your` · `i can <verb> (it\|this) [next\|now] — otherwise i` | `:168` |
| `DONE_TELLS` (false-done; needs a ledger contradiction) | `nothing (left\|more\|else)? … to do` · `everything … (is\|was) done` · `everything (requested\|else\|you asked) … done` · `complete[ ,—–-]+nothing` · `(we're\|we are\|all) done … nothing` · `that's everything` | `:171` |
| `CATEGORY_TELLS` (count, not content) | `(one\|two\|three\|four\|a few\|some\|several\|N) (item\|thing\|step\|task\|decision)s? … (is/are yours\|needs your call/attention/decision/input/sign-off\|is for you\|remains yours)` with no `:` or dash before the sentence end | `:184` |
| Opaque identifier | ≥1 bare 12-hex id with none glossed; `id: reply …` is not a gloss | `:209-236` |
| Pane-step handback | An imperative or request + a pane location or key chord, checked per sentence, with a GUI/genuine veto | `:263-302` |
| Peer-owner deferral | A peer reference + a first-person non-action ("changed nothing because …"); silent on "non-colliding" | `:311-319` |
| Jev semantic | **RETIRED** (`CC_JEV_RETIRED:-1`). Its criterion text includes "reports having IDENTIFIED remaining work without doing it". | `:369-421`, `:396` |
| Carve-outs | Assignee `:432-444`. `HARD_CORE` (credential, sudo, destructive, which-account, which-prefer …), checked message-wide `:453`, `:470`. `SOFTCALL` (`your call\|up to you\|your approval`) counts as genuine only with no `SHIPVERB` `:471`. Ship-hold needs a ledger read `:490-521`. | |
| Safety | A per-message hash latch `:598-601`. A per-session cap `ANTIDEF_MAX:-3` `:603-615`. Exit 0 on every path. | |
| What it says | A deference fire says "you presented drivable / complete-looking work as a question / hold / false-done … DRIVE it now … Re-answer by DOING it, or by naming the ONE specific irreducible blocker" (`:637`). Each arm has its own corrective (`:623-638`). | |

### 1.3 Test coverage

The tell corpus (`tests/anti-deference-nudge.bats:107-132`) has 16 fixtures, and every one is a
question or hold sentence ("Want me to run the tests next?", "Holding for your review …"). None of the
61 + 9 anti-deference tests, nor any of the 78 session-continue tests, has a fixture that is a
first-person numbered plan, a stated conviction on the agent's own fix, or a follow-on clause on a ✅
close (`grep '^@test'` listing). The Jev suite proves the retired arm makes no call (`jev-…bats` test 9).

## 2. What fired in the incident (IDL, measured)

Source: `~/.claude/autonomy/idl.jsonl` and the rotated `idl.jsonl.20261018T105203Z.gz`, filtered on
sid `5759497b`.

| Stop (UTC) | Message | anti-deference | session-continue | completion-assert |
|---|---|---|---|---|
| 05:59:29 | "I didn't change anything. The fix is … I'm about 70% sure" | `abstained no-tell` | no row (silent path) | `abstained no-close-tell` |
| 06:03:02 | "What I'd do, in order: 1. … over 90% sure … 2. … 3. …" | `abstained no-tell` | no row | no row |
| 06:04:17 | "Yes to both … What the skill would do: 1. … 5." | `abstained no-tell` | no row | `abstained no-close-tell` |
| 13:18-13:21 | (landing turns) | `no-tell` ×5 | `fired ship-floor` ×2, `ship-floor-latched` ×3 | `fired false-done` ×3 |
| 13:27:43 | (dirty A4-tokens.md) | `no-tell` | `armed mechanical-dirty`, `fired continue`; the agent ran `session-continue.sh clear` at 13:27:54. The file was committed later in `1e7461db7`, so nothing was lost. | |
| 14:19:10 | | `no-tell` | `ship-floor-budget` (spent) | `no-close-tell` |
| **14:27:47** | **"✅ Good to close: yes. Nothing of mine is open. Follow-on: the implementation waves in README §5 haven't started, because this pass was research only."** | **`abstained no-tell`** | no row | **`abstained capped:3>=3`, rung ✅** |

Transcript evidence that no tool call followed the plan turns: in
`~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl.handed-off`,
the records after `06:03:01.260Z assistant text` and `06:04:16.097Z assistant text` are the operator's
next prompts (`06:03:14.837Z user`, `06:04:35.598Z user`).

So every hook that fired fired on landedness, and every content-reading arm abstained. Separately,
completion-assert had already spent its cap when the final close arrived (other axis).

## 3. The three strings against the matcher (measured)

**Method.** `/tmp/ax03/match.sh` pulls each `VAR='…'` assignment verbatim out of the hook source with
`grep -m1 "^VAR="` and runs `grep -ioE` on the saved message texts. The hook itself was never executed,
so no state, IDL or packet was written. The fixtures are the exact message texts, extracted with `jq`
from the two transcripts (`/tmp/ax03/m1_70pct.txt`, `m2_plan.txt`, `m3_skill.txt`, `m4_close.txt`).

| Pattern | m1 "70% sure" | m2 "What I'd do, in order" | m3 "skill would do" | m4 "Follow-on: … haven't started" |
|---|---|---|---|---|
| TELLS | – | – | – | – |
| DONE_TELLS | – | – | – | – |
| CATEGORY_TELLS | – | – | – | – |
| OPAQUE_ID | – | – | – | – |
| PEER_REF ∧ PEER_DEFER | – | DEFER only ("won't fix") | – | – |
| HARD_CORE | – | – | – | – |
| SOFTCALL | `your call` | – | – | – |
| SHIPVERB | `merge` (from "merges their output") | `merge`, `land`, `/ship` | `land`, `/ship` | `land` |
| completion-assert `CA_OFFER` | – | – | – | – |

The hook leaves at `:422` with `abstain "no-tell"` before any carve-out is evaluated.

### (1) Why "What I'd do, in order: 1. … 2. … 3." with step 1 at >90% was not caught

1. There is no question and no hold, so `TELLS` (`:168`) has nothing to bite on.
2. `CATEGORY_TELLS` needs a count-noun joined to a handover-to-the-operator phrase (`:184`). The plan
   hands nothing over; it just stops.
3. The arm built for "identified work and yielded" is retired (`:370`).
4. The stated ">90%" is never parsed. The only conviction reader in the file is inside `open_packet_B`
   (`:123-125`), which runs only on the genuine-blocker path. Its regex
   `(conviction|confidence)…N%|N% (conviction|confidence)` matched 0 of the 6 stated numbers in these
   four messages ("over 90% sure", "about 70% sure", "95% sure", measured).
5. session-continue was unarmed. The turn was read-only, which the rule classes "no auto-continue"
   (`rules:34`). The ledger rung was not 🔧/📦/🚀, so all floors returned silently (§1.1).
6. Rule-side: the F2 rule says "Above 90% there is nothing to ask: implement" (`rules:68`). It has no
   chokepoint.

### (2) Why "I'm about 70% sure" without research was not caught

1. The same `no-tell` exit applies. Its one lexical neighbour, `SOFTCALL` "your call" (about the
   settings.json half), is never consulted, because `has_tell=0` exits first (`:422` precedes `:465`).
2. Had a future arm reached the carve-out, `SOFTCALL` + no ship verb would have made the *whole
   message* "genuine" (`:471`) and silenced it. m1 avoided that only because `SHIPVERB` has no right
   word boundary (`(^|[^a-z])(push|ship|land|deploy|merge)`, `:456`) and matched "merges". The
   carve-out is message-level, so one genuinely operator-only item (the settings.json edit) would mask
   the drivable one (the in-repo deadline-print fix) in the same message.
3. Nothing reads "≤90% ⇒ research first" (`rules:68`). The rule's ledger enforcement covers only an
   ask that was *filed* (`UNCONVICTED_MINE`, `rules:68`). An unfiled "I'm 70% sure" in prose is invisible.

### (3) Why "Follow-on: the implementation waves … haven't started" was not caught

1. `DONE_TELLS` does not contain "Good to close: yes" or "Nothing of mine is open" (`:171`).
2. Even if it did, false-done needs a ledger contradiction: dirty ∨ unlanded ∨ `REMAINDER>0` (`:519`).
   The ledger was ✅ (completion-assert recorded `rung:"✅"` at 14:27:50), because the frozen scope
   was "research only". So the DoD remainder was empty by construction.
3. `CATEGORY_TELLS` lacks the words "six" and "waves", and it needs a handover phrase. The clause
   hands the work to **no one**, which is exactly why it is the defect.
4. The close contract's own template allows only `follow-on: <filed ids|none>`
   (`CLAUDE.global.md:560`). The incident clause was neither, and no arm checks that slot.
5. session-continue: rung ✅ means no floor applies; the ship floor's budget was already spent at 14:19:10.

## 4. Root causes (this axis)

1. **The lexical family covers asking, not describing (97%).** The family that matters here, a
   recommendation or plan or follow-on with no addressee, has 0 patterns. Evidence: `:168`; the
   16-fixture tell corpus `tests/anti-deference-nudge.bats:107-125`; §3 measured 0 matches; IDL
   `no-tell` ×4.
2. **The designed answer to the E0 shape is retired, and nothing replaced it (95%).** Evidence: `:370`,
   `:396`; `CLAUDE.global.md:721`: "Nothing on this box catches it … a research turn that identifies
   ten items trips no arm and closes clean."
3. **session-continue is state-gated by design, and its one content-aware lever is agent-armed (95%).**
   The rule tells the agent not to pull that lever on research turns or ✅ closes. Evidence: `:4-10`,
   `:1103`, `:1216`, `:883`; `rules:34`, `rules:217`; `CLAUDE.global.md:601`.
4. **False-done is ledger-conditioned, and the ledger inherits the frozen "research only" scope, so ✅
   is reachable (90%).** Evidence: `:519`, `:536`; IDL completion-assert `rung:"✅"` 14:27:50.
5. **Stated convictions are never read on the fire path, and the one reader misses "N% sure" (92%).**
   Evidence: `:123-125`; measured 0 of 6.
6. **The genuine carve-out is message-level, so one operator-only item can mask a drivable sibling
   (75%; latent, not what happened here).** Evidence: `:470-475`; m1 escaped it only by the `merges`
   substring hit at `:456`.

## 5. Corpus (measured)

**Method.** `/tmp/ax03/scripts/corpus.py` and `corpus2.py` (run with `python3 -I`, read-only over
transcripts) take the last main-chain assistant text of every turn that ended with no tool_use after
that text and was followed by a human prompt. That is a proxy for "the message the Stop hooks
evaluated." Inputs were all four `~/.claude*/projects/*/*.jsonl*` trees, mtime < 4 days, excluding
subagents.

Result: 542 transcripts and 1,113 rows; **902 unique by text hash** (handed-off copies duplicate some).
Detector scripts: `/tmp/ax03/scripts/detect.py` (broad) and `refined.py` (proposed forms).

| Candidate | Hits / 902 | Hand-read |
|---|---|---|
| Broad plan header incl. bare "in order:" | 6 unique | 2 TP (m2, m3) and 4 FP: three operator-addressed step lists (personal finance, a court portal) and one paid-fire option menu |
| **F2 refined** (first-person header, ≥2 numbered items, no option menu, no HARD_CORE) | **2** | **2 TP** (m2, m3) |
| Any stated conviction ≤90 near an action word | 19 | 1 TP (m1). 18 are legitimate operator decisions stating their number, as F2 *requires*. Too noisy as an arm. |
| ≤90 conviction with no ask/decision/option/id framing | 4 | 1 TP (m1), 3 ambiguous or FP |
| **F3** "I didn't change/touch …" ∧ "the fix is/fix:" | **2** | m1 (TP) and one team-assignee message (silenced by `:442`). Both are left-work shapes. |
| Conviction >90 on an own action | 4 | m2, m4, and two reso-web-app production-data asks at 95%/97%. By the rule's letter these are TP (`rules:68`: above 90 implement; cc-decide refuses N>90). By intent they may be the operator's call. |
| YES closes carrying a `Follow-on:` clause | 49 | Contract shape |
| **F1** follow-on clause with no owner, id, peer, fired, parked or none | **1 / 49** | **1 TP** (m4, the incident) |
| Opener "should we/can we …?" ∧ reply starts "Yes" | 3 | 2 TP (m2, m3), 1 FP (a preview request that was answered). Adds no recall over F2 here. |

The F1 regex gives the same answer with or without an "undriven" marker (`haven't started`,
`research only`, `out of scope`): 1 of 49. The **ownerless** test alone carries it, and it is the
contract's own rule.

## 6. Fix candidates (exact insertion points)

All three are new arms in `hooks/anti-deference-nudge.sh`. They inherit the hash latch, the
`ANTIDEF_MAX` cap, the assignee abstain (`:442`) and IDL B-3 logging. They are silent when nothing
drivable is named (the arm's predicate is the drivable-work phrase itself), so there is no
always-firing alarm. Constraint from `scripts/pipefail-sigpipe-allow.txt:12`: this file is
grandfathered at 8 `grep -q`-in-pipe sites, and the list may only shrink. So every new match drains
its input: `[ -n "$(… | grep -iE … || true)" ]`, or a here-string with `grep -c`. Never `| grep -q`
or `| head`.

### F1 `followon-undriven` (conviction 88%)

Fires when line-1-style YES verdict text carries a `Follow-on:` clause that names no owner.

```bash
# insert after :319 (end of PEER block), before the Jev block
FOLLOW_YES='good to close:?[[:space:]*]*(yes|✅)|(^|[[:space:]])✅'
FOLLOW_CL='follow-?on( work)?[[:space:]]*(:|—|–|-)[^.!?]*'
FOLLOW_OWNED='(^|[^a-z])(yours?|you|session|window|pane|filed|fired|driving|working|parked until|none|nothing)([^a-z]|$)|[0-9a-f]{12}'
has_follow=0; FOLLOW_TRIGGER=""
if [ "${ANTIDEF_FOLLOWON:-on}" != off ] \
   && [ -n "$(printf '%s\n' "$MSG" | grep -iE "$FOLLOW_YES" 2>/dev/null || true)" ]; then
  _fo="$(printf '%s\n' "$MSG" | awk "$PANE_STRIP_AWK" 2>/dev/null | grep -ioE "$FOLLOW_CL" 2>/dev/null | grep -ivE "$FOLLOW_OWNED" 2>/dev/null || true)"
  [ -n "$_fo" ] && { has_follow=1; FOLLOW_TRIGGER="$(printf '%s\n' "$_fo" | awk 'NR==1' | cut -c1-160)"; }
fi
```

- Add `[ "$has_follow" -eq 0 ]` to the Jev guard (`:371`) and `|| [ "$has_follow" -eq 1 ]` to the
  gate at `:422`.
- **Placement vs the genuine exit.** Add `&& [ "$has_follow" -eq 0 ]` to `:475`, as `has_pane`
  already does. The clause test is itself per-clause (an owned clause never matches), so an
  operator-only item elsewhere in the message stays surfaced and cannot mask the ownerless one.
- `FIRE_KIND` goes after `peer-owner-deferral` (`:538`): `elif [ "$has_follow" -eq 1 ]; then FIRE_KIND="followon-undriven"`.
- `TRIGGER` gets a case at `:568-585`.
- Reason text at `:623-638`: "Follow-on with no owner (matched: …). A ✅ close may carry only filed ids
  or none. Work you researched and named is drivable: drive it now, fire a session for it with
  `handoff-fire.sh`, or file it with `cc-backlog add --why-not-now …`, then re-close. A frozen
  'research only' scope limits what this pass writes, not whether researched work gets driven. Name an
  owner or an id and this never fires."
- **Research-program exemption.** Mirror completion-assert `_ca_rp_lib` (`hooks/completion-assert.sh:1305-1320`)
  and abstain `research-program-exempt` when `research-program.sh is-active "$CWD"`. The rule names
  the Stop hook's offer arm as abstaining there (`rules:77`).
- **False-positive analysis.** 0 of 48 owned follow-on clauses fire (measured, §5). Possible FP: a
  follow-on that is a genuine external wait phrased with no owner word ("Follow-on: waits for kitty to
  accept control commands"). The measured instance of that shape carried an id and stayed silent.
  Residual: rewording "until X" into the owned list. The cost is bounded by the latch and the cap of 3.
- **Tests** (`tests/anti-deference-nudge.bats`, using `mkfix`):
  - FIRE on m4 verbatim.
  - SILENT on these real shapes: `Follow-on: \`21ba8983cd4a\` ("fire the pane-lifecycle fix session")`,
    `follow-on: the Otto call is yours`, `Follow-on: the heartbeat-fix session (window 37) is still working`,
    `Follow-on: none`.
  - SILENT on `❌ Good to close: no — … Follow-on: X` (no YES).
  - SILENT when `ANTIDEF_FOLLOWON=off`.
  - Run all of them under a no-locale env as well (the `:216-227` lesson).

### F2 `plan-not-driven` (conviction 85%)

Fires on a first-person forward plan with ≥2 numbered items in the final message.

```bash
PLAN_HDR='(what i.?d do|here.?s what i.?d|i.?d (do|suggest|propose|recommend)[^.]{0,40}(in order|next|:)|my plan([^a-z]|$)|what the [a-z-]+ would do|the order i.?d|i would[[:space:]]*:|we.?d (do|start)[^.]{0,30}:)'
PLAN_ITEM='^[[:space:]]*([-*][[:space:]]*)?[*]*[[:space:]]*[0-9]+[.)][[:space:]]+[^[:space:]]'
PLAN_MENU='(answer|reply( with)?|say)[[:space:]]+["“`'"'"']'
has_plan=0; PLAN_TRIGGER=""
if [ "${ANTIDEF_PLAN:-on}" != off ]; then
  # header line number from the RAW message (PANE_STRIP_AWK splits sentences, which shifts line numbers)
  _pl="$(printf '%s\n' "$MSG" | grep -inE "$PLAN_HDR" 2>/dev/null | awk -F: 'NR==1{print $1}' || true)"
  if [ -n "$_pl" ]; then
    _pn="$(printf '%s\n' "$MSG" | awk -v s="$_pl" 'NR>s && NR<=s+12' | grep -cE "$PLAN_ITEM" 2>/dev/null || true)"
    case "$_pn" in ''|*[!0-9]*) _pn=0 ;; esac
    [ "$_pn" -ge 2 ] && [ -z "$(printf '%s' "$MSG" | grep -iE "$PLAN_MENU" 2>/dev/null || true)" ] \
      && { has_plan=1; PLAN_TRIGGER="$(printf '%s\n' "$MSG" | grep -ioE "$PLAN_HDR" 2>/dev/null | awk 'NR==1')"; }
  fi
fi
```

- **Wiring.** Insert beside F1. Add it to the Jev guard and the `:422` gate. It **stays behind** the
  message-level genuine exit at `:475`: a plan whose steps include a credential, sudo or value fork is
  the genuine STOP-ASK. `FIRE_KIND="plan-not-driven"` goes after F1. It is ledger-independent.
- **Reason text.** "You wrote your own ordered plan and ended the turn without starting it (matched:
  …). A plan is not a queue. Do step 1 now, unless a step is one of the genuine three; above 90%
  there is nothing to ask (rules F2). If a step must wait on data, arm it with
  `session-continue.sh set "<step>"` or fire it, and say which."
- **False-positive analysis.**
  - The broad form fired on operator-addressed step lists ("Do these in order: 1. Make sure … 2. Pick
    a precinct …"). The first-person header requirement removed all 3 (measured).
  - Option menus ("Answer \"both\" …") were removed by `PLAN_MENU`.
  - Residual risk: a plan given in answer to "what would you do?" when the operator explicitly asked
    for a proposal only. The kill-switch phrase "just do X" already covers some of this. The cost is
    one re-answer turn, bounded by the latch.
  - Retrospective lists ("What I did: 1. 2.") do not match a forward header.
- **Tests:** FIRE on m2 and m3 verbatim. SILENT on an operator TODO list, an option menu, "What I did:
  1. 2.", a plan containing "you'll need to log in", and `ANTIDEF_PLAN=off`.

### F3 `diagnosed-not-applied` (conviction 75%)

Fires on "I didn't change anything / didn't touch it" together with "the fix is / fix:".

```bash
NOAPPLY='i (didn.?t|did not|haven.?t|have not) (change|edit|touch|fix|apply)[a-z]*|(changed|edited|touched) nothing|no (code )?changes? (made|yet)'
NAMEDFIX='the fix (is|would be|here is)|(^|[^a-z])fix:|the (cure|remedy) is'
```

- **Wiring.** Both patterns must match (drain-style). Gate it behind the `:475` genuine exit, but
  apply the genuine test to the **fix sentence**, not the whole message. That way m1's settings.json
  half ("your call") cannot mask the in-repo fix. This needs one sentence split, using the
  `PANE_STRIP_AWK` splitter. `FIRE_KIND="diagnosed-not-applied"`.
- **Reason text.** "You named a fix and applied none of it (matched …). If conviction is ≤90%,
  research now until it rises above 90% (rules F2), then implement. If it still sits at ≤90%, file the
  ask with `--conviction N --receipt …`. A number in prose with no research and no filing is the
  defect."
- **False-positive analysis.** 2 hits in 902 (measured): m1 and one assignee message, which `:442`
  silences. Residual: an honest "I didn't change X. The fix is upstream's" (an external owner). Add
  `upstream|vendor|their` to a per-sentence veto.

### Validation of the bash forms above (measured)

`/tmp/ax03/scripts/bashform.sh` holds F1, F2 and F3 exactly as written above, with HARD_CORE read
verbatim from the hook. It was run over the four fixtures and over all 902 unique corpus messages
(`/tmp/ax03/msgs/c*.txt`).

- Fixtures: m1 → F3, m2 → F2, m3 → F2, m4 → F1. All four incident messages fire.
- Corpus: 5 hits. Four are the incident messages themselves (c0448-c0451). The fifth (c0052) is the
  team-assignee message, which the existing `:442` abstain silences.
- Effective fire rate: 4 / 902 = 0.44%, all of them the incident.

Two things the first draft got wrong and this version fixes:

- It took the header line number from the `PANE_STRIP_AWK` stream. That stream is sentence-split, so
  its line numbers do not match the raw message; this was the cause of the m2/m3 misses.
- `my recommendation` as a header, with a 40-line window, fired on a housing recommendation whose
  numbered list was reasons. Dropping that header and using a 12-line window removed it.

Recall beyond this incident is **unmeasured**: the corpus holds no other hand-labelled instances of
these shapes.

### Smaller items

- **F4 (70%).** Widen the `open_packet_B` conviction reader at `:123-125` with
  `|(i.?m|i am)[^0-9%]{0,24}[0-9]{1,3} ?% (sure|confident|certain)`. Today "I'm about 70% sure" is
  filed as conviction 0 (measured 0 of 6 read). Pure correctness, and it does not change fire
  behaviour.
- **F5 (50%, observe only).** `SHIPVERB` (`:456`) lacks a right boundary ("merges", "landed",
  "shipping" all match). Do not change it without re-running the P0-4b tests: it currently turns some
  genuine value-forks into ship-holds. Recorded here because it decided m1's carve-out by accident.
- **F6 (55%).** A session-continue "doc follow-on floor", inserted between `ship_floor` and
  `wake_floor` at `:1317-1322`. On an unarmed ✅/👤 idle where `session_writes_paths` includes a
  `docs/research|docs/plans` `.md` with a heading matching `implementation waves?|next steps|fix
  candidates|recommendations`, and the doc carries no id, fired-session or `Parked:` marker in that
  section, block once per (sid, blob-sha), at most 1 per session.
  - Rate: 23 of 262 research `.md` files changed in 14 days carry such a heading (measured:
    `git log --since=14.days --name-only -- docs/research | … | xargs grep -lE …`). That is roughly
    1.6 candidate events/day before silencers (estimate).
  - It overlaps the wrap-ledger axis. Prefer F1 unless the ledger axis cannot surface undriven docs.

### Rule text (net cut)

Two edits, both net cuts, measured as character counts of the replaced vs new cell:

- `rules:34` (and `CLAUDE.global.md:601`): replace "No ledger, no auto-continue, no readout. Work the
  turn itself named is not exempt (see E0 below)." (98 chars) with "No ledger, no readout. Work the turn
  names still drives (E0 below)." (≈68 chars, −30). "No auto-continue" is the phrase that reads as
  permission to stop.
- `CLAUDE.global.md:721`: once F1 and F2 land, the sentence "Nothing on this box catches it: … only
  reaches a turn carrying a lexical tell — 96% of its evaluations abstain `no-tell`." becomes false.
  Replace it with "`anti-deference-nudge.sh` blocks an unstarted own plan or an ownerless follow-on."
  (≈300 chars → ≈90).

No settings.json edits are needed. All three arms live in an already-registered Stop hook.

## Skeptic verdicts

Skeptic pass, 2026-10-18. The study was read-only. The only repo write is this appended section.
Scratch files are outside the repo: `/tmp/ax03_skeptic_pane.inc` (hook lines 263-297 and 311-313
copied verbatim), and `/tmp/ax03sk/` (`pane.sh`, `f1audit.sh`, `fx/*.txt` synthetic fixtures,
`antidef_cap.tsv`, `f6_files.txt`). The hook itself was never executed. Every fire or silence below
comes from the axis's own `/tmp/ax03/scripts/bashform.sh` or from verbatim hook regexes.

### Bottom line

The diagnosis holds: neither hook could see the three incident shapes. The detectors' precision on
the corpus also holds: I re-ran them and got the same 5 of 902, in a UTF-8 locale and with no
locale. **The fix specs do not survive as written.** F1 and F3 have a wiring bug in the FIRE_KIND
chain. F1 fires on a compliant ❌ close. F2 has no silencer, so it blocks a ⛔ decision close, a
stated park, and the agent's own compliance with F2's reason text. All three share a cap that a
single arm already exhausts in about 1 session in 10. The rule-text "net cut of ~240 chars" is
mostly in a file that is not resident.

### Root causes

| # | Verdict | Adjusted | Re-check |
|---|---|---|---|
| RC1 lexical family covers asking, not describing | **confirmed** | 95% | `/tmp/ax03/match.sh` re-run: 0 of 4 messages match TELLS, DONE_TELLS, CATEGORY_TELLS, HARD_CORE or OPAQUE_ID. I also ran the pane and peer arms through `PANE_STRIP_AWK` (`/tmp/ax03sk/pane.sh`), which match.sh does not cover: 0 of 4. IDL `no-tell` at 05:59:29, 06:03:02, 06:04:17 and 14:27:47Z, re-grepped. Two count errors: `TELLS` (:168) has **14** alternations, not 15, and the corpus has 16 fixtures (`bats:109-124`) because `should i` covers three. |
| RC2 Jev retired, nothing replaced it | **weakened** | 60% | The gap is real (`CLAUDE.global.md:721`; hook :333-335). The retirement is **not causal**, though. The hook's own retirement note (:356-365) says that over 160 real closes, not one p≥0.90 row was classed `drivable`. It also says every call returned 403 (372 calls in 25 h). An un-retired Jev would have abstained on m1-m4 too. |
| RC3 session-continue is state-gated, and its one content lever is agent-armed | **confirmed** | 93% | `:4-10`, `:1103`, `:1108-1110`, `:1216`, `:883` and floor order `:1316-1325` all read as cited. The IDL has no session-continue row at the 4 Stops. Stronger than stated: the agent did use the lever, then cleared it as `rules:217` demands on ✅ (`cli-clear` at 10:33:27, 12:16:17, 12:49:59, 13:17:30 and 13:27:55Z). One nuance: the 14:19:10 `ship-floor-budget` is irrelevant at 14:27. At rung ✅, `ship_floor` returns at the rung gate (:1216) before any budget check. |
| RC4 false-done is ledger-conditioned; ✅ reachable | **confirmed (mechanism made precise)** | 85% | `:519` and `:536` are as cited. The IDL row at 14:27:50Z is `capped:3>=3`, `rung:"✅"`. Precision: REMAINDER counts unchecked `- [ ]` DoD boxes (`scripts/wrap-ledger.sh:924-931`), and the `Scope (frozen):` wording is never read. ✅ was reachable because no §5 wave ever became a DoD box, not because of the words "research only". |
| RC5 stated convictions never read on the fire path | **weakened** | 65% | Factually right, with a count fix. The four messages state **5** convictions, not 6 (m1 70; m2 90 and 70; m4 95 and 70; measured by `grep -oiE`), and the :123-125 reader reads 0 of 5. But it is not a cause: the reader runs only inside `open_packet_B` on the genuine path (:475-487), and no message reached it. "Rule F2 has no chokepoint" is the real point, and RC1 already covers it. |
| RC6 genuine carve-out is message-level (latent) | **confirmed** | 75% | :470-475 as cited. match.sh: m1 has SOFTCALL `your call` and SHIPVERB ` merge` (from "merges"), so :471 leaves `hard=0`. Not causal here, as the axis says. |

### Fix candidates

**F1 `followon-undriven`: weakened, 88% → 62%.** The precision claim reproduces: `/tmp/ax03sk/f1audit.sh`
found 69 corpus messages with a YES/✅, 49 with a follow-on clause, and 1 ownerless (c0451, the
incident). The other 48 are honestly owned: 22 `none`, 13 by id, and the rest by you/yours, a
session or "filed". Five defects:
1. **Wiring bug (implementability).** The proposal adds `&& has_follow -eq 0` to :475 "the way
   has_pane does", but puts the FIRE_KIND branch after peer (:538). `has_pane` escapes because it is
   *first* in the chain (:525). The chain reaches `elif [ "$hard" -eq 1 ]` (:529) before the peer
   slot. So a message with hard=1, has_follow=1 and has_id=0 gets `FIRE_KIND="opaque-identifier"`,
   with an empty TRIGGER and the reason "you handed the operator 0 bare hex ids" (:626). An example
   is a close that also says "raising the timeout requires your approval". The F1 branch must sit
   before :529, or :529 must require `has_id -eq 1`.
2. **Fires on a compliant ❌ close.** `FOLLOW_YES` includes `(^|[[:space:]])✅` anywhere. The contract
   requires line 2 to relay the rung glyph (`CLAUDE.global.md:559-562`), and that glyph is often ✅
   under a ❌ line 1. Fixture `fx/q1` ("❌ Good to close: no — … mine to drive next" / "✅ Complete
   and landed" / "Follow-on: … haven't started") **fires F1**. The single-line variant `q2` is silent,
   so the planned test "SILENT on ❌ … Follow-on: X" passes only in single-line form. Corpus: 8 of 65
   NO-verdict closes carry a ✅ elsewhere (measured, head -1 plus grep). The cure is to anchor
   FOLLOW_YES to line 1.
3. **Evadable, and it punishes honesty.** These fixtures stay silent: dropping the clause (`p4`),
   relabelling it `Next:` (`p5`), and incidental owner words common in this repo: `session-start`
   (`p1`), `working-tree` (`p6`), `nothing driven yet` (`p2`), `the waves you saw` (`p3`). An arm
   that fires only when the agent *names* the follow-on teaches the model to omit it. The hook's own
   header warns of exactly this (:30-31, "a nagging hook trains the model to route around it").
4. **Shared cap.** Across the IDL files from 2026-10-13 to 2026-10-18 plus the live file, the hook
   logged 852 `capped` suppressions against 190 fires. 851 of the suppressed were `opaque-identifier`.
   9 of the 96 sessions that fired at least once reached the cap, and one session holds 816 of the 852
   (measured, jq over the IDL, `/tmp/ax03sk/antidef_cap.tsv`). A new arm inherits this silencing.
   It is the same mechanism that silenced completion-assert at the incident close.
5. **The reason text offers filing as an equal discharge** ("or file it with `cc-backlog add`").
   That conflicts with `rules:68` ("Above 90% there is nothing to ask: implement") for the ≥85-95%
   waves that are the incident's subject.
Constraints: it does not block a ⛔ decision (a ⛔ close names its owner or id). A stated park is
silent through `parked until`. The research-program exemption would not have silenced the incident:
`~/.claude/autonomy/research/programs.json` holds only `truememory-2-0` (tm2-plan roots). No existing
fixture in `tests/anti-deference-nudge.bats` or `tests/jev-anti-deference-arm.bats` matches its
keywords (grep), so no test contradicts it.

**F2 `plan-not-driven`: weakened, 85% → 45%. As written it violates the brief's constraints.**
The corpus precision reproduces (2 of 902, c0449 and c0450). But it has **no silent path for a
legitimate stop**, and synthetic fixtures run through the axis's own `bashform.sh` all **fire**:
- `p8`: a ⛔ close on decision `0123456789ab (raise the timeout?)` plus "What I'd do once it is
  answered: 1. 2." The glossed id gives has_id=0, and HARD_CORE does not match, so the :475 exit does
  not save it. This blocks a genuine operator decision.
- `p9`: "Parked: …, until tomorrow's load data lands (eb3d6f848add …)" plus a plan. This blocks a
  deliberate stated park.
- `p10`: "Step 1 is armed: session-continue.sh set …" plus a plan. That is the arm's **own
  prescribed remedy** ("arm it with `session-continue.sh set` … and say which"), so it **fires on
  compliance**. For m2 itself, step 2 waits on "a day of data", so after doing step 1 the agent's
  restated plan re-fires (new hash) up to the cap.
- `p11` plan-only on request, and `p12` "I'd suggest you do these in order: 1. Open the Fidelity
  app" (operator-addressed under a first-person header).
The FP note's "The kill-switch phrase 'just do X' already covers some of this" is **false**.
`KILL_RE` exists only in `hooks/session-continue.sh:386`. anti-deference-nudge.sh reads no operator
message and no `permission_mode` (grep: no match), so plan mode is not exempt either. Minor:
`PLAN_MENU` puts the multibyte `“` inside a bracket expression, the locale trap documented at
:216-227. I measured no difference on the corpus in either locale. Needed silencers: a ⛔ line 1, a
12-hex id, `Parked:`, `armed`, `session-continue.sh set`, `fired`, and permission_mode=plan.

**F3 `diagnosed-not-applied`: weakened, 75% → 45%.** The corpus result reproduces (2 of 902: c0448
is m1, c0052 is the assignee message). Defects:
- The spec contradicts itself. It says "gate it behind the :475 genuine exit" and also "apply the
  genuine test to the fix sentence", but a per-sentence test requires bypassing the message-level
  exit. That bypass hits the same :529 `opaque-identifier` mislabel as F1.
- Fixture `p13` ("I didn't change anything. The fix is a settings.json edit … that file is yours to
  approve") **fires**. Neither HARD_CORE nor SOFTCALL knows "yours to approve", and a settings.json
  edit is operator-only on this box.
- m1 fires only by luck: SHIPVERB matches "merges" (RC6). If F5 is fixed, m1 becomes genuine and F3
  goes silent on it.

**F4 widen the `open_packet_B` reader: weakened, 70% → 45%.** The widened regex reads 4 of 5
(misses "was only at 70% on it"). "Does not change fire behaviour" is true. "Pure correctness" is
not. The reader keeps the **first** number (`awk 'NR<=1'`, :125), and m4 would yield 95. cc-decide
refuses N>90 (:121-122 and `rules:68`), so the packet open fails. That produces the bare idle
open_packet_B exists to prevent. The packet's conviction must be bound to the fork's sentence, not
to the message.

**Rule text: weakened, 70% → 55%.** `rules:34` is a measured cut of 97→67 chars (−30, `wc -m`).
The deployed `~/.claude/rules/10-session-close.md` is byte-identical to the source (diff). But the
`CLAUDE.global.md:721` sentence is **not resident**. `grep -c 'Nothing on this box catches it'`
gives 0 for `~/.claude/CLAUDE.md` (the slim variant, 28,894 B) and 1 for `~/.claude/CLAUDE.full.md`.
So the resident cut is about 30 chars, not about 240. Also, `CLAUDE.global.md:601` carries different
text ("**No ledger, no auto-continue.** Answer and yield — but *yield* governs…"), so the
"replace in both" string edit does not apply there. It is still a net cut, so it is compliant.

**F6 doc follow-on floor: weakened, 55% → 40%.** The insertion point is confirmed (`:1317` ship
floor, `:1322` wake floor). The count reproduces approximately: 26 of 271 changed docs/research .md
files over 14 days (`git log --since=14.days --name-only` plus a heading grep), against 23 of 262.
The `Parked:` / fired / id marker convention it depends on does not exist yet. Until it does, F6 is
the moderate-rate alarm the axis itself rates it as.

### Measurements

| Measurement | Verdict | Note |
|---|---|---|
| No tool_use after 06:03:01 or 06:04:16Z | confirmed | jq over the `.handed-off` transcript: the next main-chain records are user prompts at 06:03:14.837Z and 06:04:35.598Z. The operator's next prompt arrived 12-19 s after each Stop, so a block would race a queued prompt. |
| IDL rows at the 4 Stops | confirmed, with an addition | The 14:27:50Z row carries `suppressed_arm:"handoff"`. CA_HANDOFF (`completion-assert.sh:467`, `needs your`) matched m4's settings.json sentence, not the follow-on clause. |
| match.sh 0 of 4 | confirmed | Re-run as cited. Pane and peer arms also checked (0 of 4). |
| Reader 0 of 6 | weakened | 0 of **5**: the messages state 5 convictions. |
| Corpus 542 / 1,113 / 902 | confirmed in part | 902 files in `/tmp/ax03/msgs` (ls). 542 and 1,113 were not re-derived. |
| bashform 5 of 902 | confirmed | Re-run in a UTF-8 locale and with no locale: same 5 hits, and all 4 fixtures fire. |
| 49 YES closes with a follow-on, 1 ownerless | confirmed | f1audit.sh: 69 YES-or-✅ messages, 49 with a clause, 1 ownerless. |
| 19 of 902 at ≤90 and 4 of 902 above 90 | weakened | Not re-run (detect.py and refined.py logic not re-audited). |
| 23 of 262 docs | confirmed (≈) | 26 of 271 today. |
| Test counts 61 / 9 / 61 / 5 / 12 | confirmed | `grep -c '^@test'`. |
| Rule cut ≈240 chars | weakened | Resident cut is −30 chars (measured). The rest is in non-resident CLAUDE.full.md. |

### Missed by the axis

1. The FIRE_KIND-chain mislabel (`:529` precedes the proposed F1 and F3 slots) whenever an arm
   bypasses :475.
2. `FOLLOW_YES` matches the line-2 rung glyph, so F1 fires on compliant ❌ closes (8 of 65 NO closes
   carry a ✅).
3. F2 has no silencer for ⛔, decision ids, `Parked:` or an armed or fired continuation. It fires on
   its own remedy.
4. anti-deference-nudge reads neither the operator's message (no kill-switch) nor `permission_mode`
   (plan mode).
5. The shared `ANTIDEF_MAX` cap: 852 suppressed vs 190 fired, 9 of 96 sessions capped. New arms
   inherit it, and the same mechanism silenced completion-assert at the incident close.
6. Completion-assert's suppressed arm at 14:27:50Z was `handoff`, on the settings.json line.
7. Omission and relabel evasion of F1, and the "name it and get blocked" incentive. A ledger-side
   or doc-side signal (F6, or axis 04) cannot be evaded by rewording the close.
8. F4's first-number pick can turn a packet open into a cc-decide refusal.
9. The :721 sentence is not resident, so it does not count toward the budget.
10. Jev's retirement was not causal: it had zero measured `drivable` detections and 403'd on every
    call.
