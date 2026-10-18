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
