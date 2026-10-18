# Axis 02: completion-assert.sh and hooks/lib/close-shape.sh vs the 2026-10-18 close

Scope: map every arm of `hooks/completion-assert.sh` and the matchers in `hooks/lib/close-shape.sh`.
Answer why none of them blocked `✅ Good to close: yes. Nothing of mine is open. Follow-on: the
implementation waves in README §5 haven't started, because this pass was research only.`, and
propose a new arm that can be built.

Read-only on the repo. Every replay ran on copies under `/tmp/ca-axis02/`, with all state seams
(`COMPLETION_STATE_DIR`, `COMPLETION_IDL`, `CC_IDL`, `CC_FIRED_DIR`, ledger and backlog stubs) pointed
into `/tmp`. The same seams `tests/completion-assert.bats:13-89` uses.

## 0. Headline (answer first)

1. **The hook did try to block the incident close, but its budget was already spent.** The IDL
   record for the incident Stop (close at `2026-10-18T14:27:47.478Z`) reads:
   `{"ts":"2026-10-18T14:27:50Z","hook":"completion-assert","sid":"5759497b-…","disposition":"abstained","reason":"capped:3>=3","suppressed_arm":"handoff","rung":"✅","facts":"","class":"assert","count":3,"max":3}`
   (measured: `grep 5759497b ~/.claude/autonomy/idl.jsonl | grep completion-assert`). The three
   `assert` slots went on three ledger 📦 fires at 13:18:34, 13:19:02 and 13:19:40Z ("1 commit(s) YOU
   wrote are committed-but-unlanded"), 68 minutes earlier. From then on the `assert` class was silent
   for the whole session (`completion-assert.sh:1608-1635`). Conviction 97%.
2. **Even with budget left, the arm that would have fired was the wrong one.** D1 (`handoff`) matched
   `needs your` in line 13 (`The one change that needs your hand is raising the dispatcher's timeout…`,
   which is the 70% settings.json item), not the follow-on clause. A hermetic replay with a fresh latch
   fires `arm:"handoff"`, and its reason only asks for a `cc-backlog needs` row for that step. With
   line 13 removed, the same close passes with `ledger-clean` (measured: `/tmp/ca-axis02/replay.sh` A/B/C, §3).
   Conviction 95%.
3. **No arm reads the follow-on clause.** D6 checks only that a `good to close` anchor exists and that
   its value is not a `<placeholder>` (`close-shape.sh:82-107`). `close_verdict_polarity` reads only the
   first token after the anchor (`close-shape.sh:135-139`). D3's `CA_YES_HEDGE` looks only at the word
   right after `yes` (`completion-assert.sh:373`). D4 needs an offer phrase (`:1280`). In 1,660 + 311
   lines, `follow-on` appears only in comments and in the template. Conviction 95%.
4. **The contract itself licenses the pattern.** The template line `close-shape.sh:179` reads
   `Good to close: <yes — nothing of mine is open; follow-on: <filed ids, each expanded in plain English|none> | …>`.
   The live rule `~/.claude/rules/10-session-close.md:146` (byte-identical to
   `CLAUDE.rules.slim.10-session-close.md`, measured: `diff -q`) says *"A qualification goes in S2's
   `follow-on:` clause, beside the assertion."* So a YES with undriven work in its trailing clause is
   the documented shape, not a dodge. Conviction 85%.
5. **Proposed fix:** a new arm D8, `followon`, with its own cap class. It fires on a YES verdict whose
   first real `follow-on:` value is not none, not filed ids, not a fired pane, not a ⛔ decision, not
   owned by someone named, and not a stated park. Prototyped against copies. It fires on the incident,
   **including the capped state the incident was in**, and passes all 11 controls (§5). Estimated
   firing rate: 4 of 556 YES-with-follow-on closes over 14 days (0.7%). Method: Python regex
   approximation over 1,954 transcripts (§6).

## 1. How the hook reads its inputs and emits a block

| Step | Where | What |
|---|---|---|
| stdin | `completion-assert.sh:136,169-184` | one jq pass pulls `session_id`, `transcript_path`, `cwd` |
| kill switch | `:206-268` | last non-meta, non-machine user record (`ca_last_user_msg`, `jq -c … \| tail -1`) matched against `CA_KILL_RE` ⇒ `abstain kill-switch` |
| last assistant text | `:282-286` | `jq -c 'select(.type=="assistant" and (.isSidechain != true)) \| ([.message.content[]? \| select(.type=="text") \| .text] \| join("\n")) \| select(. != "")' "$TP" \| tail -1`, then decoded into `$MSG`. Compact JSON keeps one record per line. |
| first two lines | `:374-380` | `ca_first` / `ca_second` (left-trimmed, non-empty) |
| quote-stripped view | `:441-442` | `MSG_UNQ` drops backtick, "…" and “…” spans (D1/D4 only) |
| ledger | `:513-594` | `wrap-ledger.sh --machine [--session SID]`, fields read with `lfield` |
| block | `:1659` | `jq -nc --arg r "$reason" '{decision:"block",reason:$r}'`; **every path exits 0** (`:91-92`) |
| abstain | `abstain "<reason>"` (hooks/lib/idl-log.sh) | one IDL line `{disposition:"abstained",reason:…}`, exit 0 |
| latch/cap | `:1550-1635` | `$STATE_DIR/<sha(CFG\|SID\|CWD)[:16]>.fired`, lines `<msg-hash16> <class>`; same hash ⇒ `latched-already-fired`; per-class count ≥ max ⇒ `capped:…` with `suppressed_arm`, `rung`, `facts` |

## 2. Arm map

Gates run in file order. An `abstain` ends the run.

| # | Arm (IDL `arm`) | Trigger / inputs | Blocks | Output |
|---|---|---|---|---|
| G0 | kill switch | operator's last prompt matches `CA_KILL_RE` (`:206`) | nothing (abstain) | `kill-switch` |
| R | research relay (`relay`) | sid has a route record (`:308-314`); `router.py relay-check` rc 1 (`:322-350`) | a relay reply adding items | own class `relay`, `COMPLETION_RELAY_MAX`=2; rc 3 ⇒ `relay-turn-relayed` abstain (`:329`) |
| G1 | close-tell gate | `$MSG` matches `CLOSE` (`:355`), or line 1 matches `CA_SETTLED` (`:360`) and not `CA_VERDICT_NO` (`:372`) (`:394-397`) | — | `no-close-tell` (1,009 of the 1,343 records in the current `idl.jsonl`, 2026-10-18 12:16Z→20:22Z, measured: jq tally) |
| G2 | genuine blocker | `GENUINE` regex over `$MSG` (`:400-401`): credential, sudo, destructive migration, "which option", "would you prefer"… | — | `genuine-blocker`. **This is the gate that keeps every arm silent on a real operator decision.** |
| L | ledger contradiction (`ledger`) | `contra=1` from: dirty mine (`:952-976`), unlanded mine (`:981-1027`), `REMAINDER` (`:1028`), `CUSTODY_OPEN` (`:1033-1034`), `FILED_MINE` (`:1042-1043`), `UNCONVICTED_MINE` (`:1053-1054`), `CLOSE_FLOOR` (`:1067-1069`), `RUNG=🚀` (`:1091-1107`), `RUNG=⛔` (`:1131-1135`) | done-claim over git/store facts | class `assert`, `COMPLETION_MAX`=3. Double-block yield to session-continue (`:1169-1192`) |
| D2 | `fence` | column-0 line whose first token is an operator verb or `ENV=VAL`, outside a tagged fence (`:1202-1226`) | a bare command in prose | `assert` |
| D1 | `handoff` | `CA_HANDOFF` (`:467`) over negation-stripped `MSG_UNQ` (`:477-479`) ∧ `cc-backlog list --blocked --json` is `[]`-affirmative with no row for SID (`:1231-1243`) | operator work handed over in prose | `assert` |
| D3 | `hedge` | **line 1 only**. Verdict line: text before the anchor matches `CA_SETTLED`∧`CA_RETRACT`, or `CA_YES_HEDGE` (`:1259-1265`). Non-verdict line 1: `CA_SETTLED`∧`CA_RETRACT` (`:1266-1270`) | a yes that withdraws itself on line 1 | `assert` |
| D4 | `offer` | `CA_OFFER` (`:1280`) ∧ `CA_WORKLEFT` (`:1281`) on the non-offer lines (`:1285-1288`); exempt when a research program is active (`:1338-1343`) | named work offered, not driven | `assert` |
| D5 | `placeholder` | a run-line (lone inline span, `▶`, or the line after "run this") holding `<…>` (`:1379-1402`) | an unpasteable command | `assert` |
| D6 | `shape` (tokens `good-to-close-verdict`, `line-1-rung`, `verdict-first`) | `contra_shape=0` ∧ RUNG∈{✅,👤} ∧ not an assignee ∧ positive write evidence ∧ origin (`:1428-1455`). Tokens: `close_shape_missing` (`close-shape.sh:82-107`); rung glyph contained in line 1 (or lines 1-2 under a verdict line 1, `:1476-1484`); `close_verdict_not_first` (`close-shape.sh:158-161`, `:1489-1492`) | a missing verdict, a missing rung glyph, or a NO under a done-reading line 1 | class `shape` (`COMPLETION_SHAPE_MAX`=2). When verdict-first is the only token: class `verdict` (`COMPLETION_VERDICT_MAX`=2) (`:1608-1612`) |
| D7 | `act` | `contra_shape=0` ∧ RUNG=👤 ∧ not an assignee ∧ no `▶`/`ACT:` in the first 3 unfenced lines (`close-shape.sh:242-268`, `:1536-1541`) | a 👤 close whose act is not its own line | class `act` only when D7 fires alone (`:1613-1615`) |
| — | final abstain | none of contra, d1…d7 (`:1546-1548`) | — | `ledger-clean[:exonerated:…][:research-program-exempt:…]` |

Notes from the map:

- **Class precedence** (`:1608-1615`): `verdict` (D6 verdict-first alone) > `shape` (any D6, even
  with d1-d5) > `act` (D7 alone) > `assert`. **D1/D3/D4/D5 have no class of their own.** They draw on
  the same `assert` budget as the ledger's mid-session 📦 convictions. That is the same starvation
  item 3b464e94b3ff fixed for D6 (`:1560-1568`), still open for the four arm-2 prose arms. In the
  Oct 16-18 window, 344 `capped:assert` abstains against 181 fires (all classes). 8 of those
  suppressions named a prose arm (`ledger+handoff` 5, `✅ handoff` 2, `👤 handoff+act` 1) (measured: jq
  over `idl.jsonl.20261018T105203Z.gz` + `idl.jsonl`, 4,065 completion-assert records,
  2026-10-16T08:16Z→10-18T20:22Z).
- **What reads the verdict's content:** `close_shape_missing` (presence plus a not-a-placeholder value),
  `close_verdict_polarity` (yes/no/mixed/none from the first token after the anchor, `close-shape.sh:124-142`),
  `close_line_reads_done` (line 1 only), D3's `CA_YES_HEDGE` (the word immediately after `yes`).
  **None of these reads anything after the first token of the verdict value.**

## 3. Why the incident close passed every arm (measured replays)

The close text, as extracted from the transcript: 15 lines, saved to `/tmp/ca-axis02/close.txt` (jq on
`~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl`,
record `timestamp=="2026-10-18T14:27:47.478Z"`).

Hermetic replay (`/tmp/ca-axis02/replay.sh <tag> <text> [rung] [precap]`: stub ledger RUNG=✅ all-zero,
one Edit record so D6's write gate holds, backlog stub `[]`, origin):

| Run | Input | Result (measured) |
|---|---|---|
| A | incident close, fresh latch | `fired`, `arm:"handoff"`, class `assert`. Reason: D1's "File each operator-only step — cc-backlog needs …" |
| B | incident close minus line 13 (`needs your hand`) | `abstained ledger-clean`: no arm sees the follow-on clause |
| C | incident close, 3 `assert` lines pre-seeded | `abstained capped:3>=3, suppressed_arm:"handoff", rung:"✅"`, the exact live record |
| D | control `Everything is done and landed on trunk.` | `fired arm:"shape"`, which proves the replay reaches D6 |

Arm by arm on the incident text (measured: lib calls and greps on `/tmp/ca-axis02/close.txt`):

- G1: `✅` is in `CLOSE`, so it passes.
- G2: no `GENUINE` match, so it passes.
- L: the live ledger read ✅ (the `rung` in the IDL record), so `contra=0`.
- D6: `close_shape_missing` ⇒ `[]`. Line 1 contains `✅` = RUNG. `close_verdict_polarity` ⇒ `yes`, so
  `verdict-first` passes. **The arm treats this close as compliant.**
- D3: the text before the anchor is `✅ `, so `CA_RETRACT` does not match. `CA_YES_HEDGE` needs
  `but|except|…|until|pending…` right after `yes[^a-z]+`, and gets `. Nothing`. Passes.
- D4: `CA_OFFER` matches 0 lines. The close offers nothing; it just stops.
- D7: RUNG is not 👤, so not evaluated.
- D1: matches line 13 only (`grep -noiE "$CA_HANDOFF"` ⇒ `13:needs your`). It fires uncapped and is
  capped live. It is aimed at the settings.json timeout, not the §5 waves.

Why D4 and D1 cannot be stretched to cover this: D1's remedy is filing an operator step. The §5 waves
are agent-drivable, so filing them as `needs-human` is the wrong instruction (D1's own reason opens
"file it only if you genuinely cannot"). D4 is keyed to an offer phrase, and the incident has none.
The pattern is a **declarative stop**, not an offer.

Earlier instances in the same session ("What I'd do, in order…", 06:03Z; the board diagnosis at
05:59Z) abstained at G1. Live record `{"ts":"2026-10-18T05:59:29Z",…,"reason":"no-close-tell"}`
(measured: gz IDL grep). Those turns have no verdict and no close token, so they are outside this
hook's reach by construction. That is a session-continue / E0 problem (other axes), not a
completion-assert arm.

## 4. Root causes on this axis

| # | Claim | Evidence | Conviction |
|---|---|---|---|
| RC1 | No arm parses the content of the follow-on clause. A YES plus any trailing prose passes D6/D3. | `close-shape.sh:82-107,124-142`; `completion-assert.sh:373,1259-1270`; replay B `ledger-clean` | 95% |
| RC2 | The close template and the live rule define the follow-on clause as the place for qualifications, so undriven work rides in a YES legitimately. | `close-shape.sh:179`; `~/.claude/rules/10-session-close.md:22,146`; `CLAUDE.global.md:560,928` | 85% |
| RC3 | Cap starvation: arm-2 prose arms (D1/D3/D4/D5) share the `assert` budget with ledger convictions, so a session that had three 📦 fires has no budget left at its terminal close. | live IDL `capped:3>=3 suppressed_arm:handoff` at 14:27:50Z; class table `:1608-1615`; replay C | 97% |
| RC4 | Every ledger term is a git or store fact. A doc this session wrote that lists undriven waves is not a ledger fact, so `contra` stays 0 at ✅. | contra terms `:935-1135`; IDL `rung:"✅"`, `facts:""` | 90% |
| RC5 | The one arm that fired (D1) points at the wrong object (a 70% operator step), so even uncapped the hook would have taught "file a needs row", not "drive §5". | replay A reason text; `CA_HANDOFF` match on line 13 only | 90% |

## 5. Proposed arm D8 `followon`: design, insertion points, prototype

### 5.1 Predicate

```
D8 := CC_CLOSE_FOLLOWON != 0
    ∧ contra_shape == 0                 (the ledger arm, if any, owns the demand: same gate as D6/D7)
    ∧ RUNG ∈ {✅, 👤}                    (⛔ already contra=1; 📦/🔧/🚀 already convicted)
    ∧ ¬ _ca_assignee                    (a teammate's close is its lead's harvest)
    ∧ ¬ research-program active (cwd)   (certificate residuals are not open work: ruling 83adb541ea19)
    ∧ close_followon_undriven "$MSG"    (lib, below)
close_followon_undriven := close_verdict_polarity == yes
    ∧ first unfenced `follow[- ]?on…:` value that is not empty and not `<placeholder>`
      matches NONE of:
        none      ^(none|nothing|n/a|no follow-on|zero)
        driven    12-hex id | pane N | cc-decide | dotted tracker id (health.call-…-949) | ⛔
        owned     yours | your call/decision/step/hand/list | for you | operator | the lead | owned by | goes to | on your
        park      parked | not-yet-true | needs-credential | needs-human | no-capacity | waiting on/for | blocked on/by
```

Inherited silences (no new code): G0 kill switch, G2 `GENUINE` (a real operator decision in prose ⇒
the whole hook abstains), a NO verdict (polarity ≠ yes), a ⛔ token or a `cc-decide` id in the clause,
fenced text, and quoting the template (`<…>` value).

Why each exemption exists:
- **owned**: operator-owned prose is D1's territory, and D1 already checks the store for it.
- **park**: the four `--why-not-now` classes plus "waiting on" are the rules' stated park vocabulary.
  "research only" and "out of scope" are deliberately **not** parks (see the D4 reason at `:1651`:
  "'out of scope' is not a reason").

### 5.2 Insertion points (current file:line)

1. `hooks/lib/close-shape.sh`: after `close_verdict_not_first` (ends `:161`), before `close_shape_ok`
   (`:163`), add the five `_CS_FO_*` constants and `close_followon_undriven` (prototype:
   `/tmp/ca-axis02/proto/followon.sh`, reproduced below). After `close_shape_reason` (ends `:311`),
   add `close_followon_reason <value>`.
2. `hooks/lib/close-shape.sh:179` template: change the yes branch's follow-on slot to
   `follow-on: <none | filed ids · fired panes · ⛔ decisions — anything undriven makes this a no>`.
   Keep the leading `<` and trailing `>` so `close_shape_ok "$(close_shape_template)"` stays rc 1
   (pinned by `tests/completion-assert.bats` "close-shape UNIT: quoting the template").
3. `hooks/completion-assert.sh`: insert the D8 block **after D7 (`:1541`) and before the comment at
   `:1543`**. It needs RUNG, `contra_shape`, `_ca_assignee`, `_ca_rp_active` and
   `_ca_source_close_shape`, all of which are defined above that point.
4. `:1546-1547` final abstain: add `|| [ "$d8" -eq 1 ]`.
5. `:1601` arm string: add `[ "$d8" -eq 1 ] && arm="${arm:+$arm+}followon"`.
6. `:1612` class selection: insert
   `elif [ "$d8" -eq 1 ]; then CLASS=followon; CLASS_MAX="${COMPLETION_FOLLOWON_MAX:-2}"` right after
   the `shape` line. **D8 claims its own class even when D1 also fires.** That choice is what makes it
   reach the incident (RC3). Same precedent as `shape` claiming its class over d1-d5.
7. `:1654` reasons: append `[ "$d8" -eq 1 ] && reason="${reason:+$reason }$(close_followon_reason "$_d8_val")"`.
8. Header `:95-105` env seams: document `CC_CLOSE_FOLLOWON` (kill switch) and `COMPLETION_FOLLOWON_MAX`.

The prototype lib function (measured working under macOS `awk version 20200816`):

```bash
_CS_FOLLOWON='follow[- ]?ons?[^:]{0,24}:'
_CS_FO_NONE='^[*_` ]*(none|nothing|n/?a|no follow-?ons?|zero)([^a-z]|$)'
_CS_FO_DRIVEN='[0-9a-f]{12}|pane[ #]*[0-9]+|cc-decide|[a-z]+[.][a-z0-9-]+-[0-9]+'
_CS_FO_OWNED='(^|[^a-z])(yours?|your (call|decision|step|hand|list)|for you|operator|the lead|lead owns|owned by|goes? to|on your)([^a-z]|$)'
_CS_FO_PARK='(^|[^a-z])parked([^a-z]|$)|not-yet-true|needs-(credential|human)|no-capacity|waiting (on|for)|blocked (on|by)'
close_followon_undriven() {
  [ "$(close_verdict_polarity "${1:-}")" = yes ] || return 1
  printf '%s' "${1:-}" | awk -v fo="$_CS_FOLLOWON" -v none="$_CS_FO_NONE" -v drv="$_CS_FO_DRIVEN" \
                             -v own="$_CS_FO_OWNED" -v park="$_CS_FO_PARK" '
    BEGIN { fence = 0; found = 0 }
    { t = $0
      if (t ~ /^[ \t]*```/) { fence = !fence; next }
      if (fence) next
      l = tolower(t)
      if (!match(l, fo)) next
      v = substr(t, RSTART + RLENGTH); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      lv = tolower(v)
      if (lv == "" || lv ~ /^</) next
      if (lv ~ none || lv ~ drv || index(v, "⛔") > 0 || lv ~ own || lv ~ park) exit
      print v; found = 1; exit }
    END { exit(found ? 0 : 1) }'
}
```

**Trap found while prototyping (measured):** a `\.` inside an `awk -v` value is unescaped to `.` by
awk, so a first draft `[a-z]+\.[a-z0-9-]+-[0-9]+` matched `am-31` and `waves 1-5` and exempted both
fire cases. Use bracket classes (`[.]`) in every `-v` regex, as the existing lib already does with
`[[:space:]]`.

The D8 hook block (prototype as patched into the copy by `/tmp/ca-axis02/patch.py`):

```bash
d8=0; _d8_val=""
if [ "${CC_CLOSE_FOLLOWON:-1}" != 0 ] && [ "$contra_shape" -eq 0 ] \
   && { [ "$RUNG" = "✅" ] || [ "$RUNG" = "👤" ]; } && ! _ca_assignee \
   && ! { [ -n "$CWD" ] && _ca_rp_active "$CWD"; }; then
  if _ca_source_close_shape && command -v close_followon_undriven >/dev/null 2>&1; then
    if _d8_val="$(close_followon_undriven "$MSG")"; then d8=1; fi
  fi
fi
```

Reason text (one paragraph, no backticks per the SC2016 note at `close-shape.sh:299-304`): *"Your
verdict is yes, but its follow-on clause names work nobody is driving: "<value>". A follow-on clause
may hold only none, filed backlog ids, a pane you fired that is driving it, or a ⛔ decision filed with
cc-decide open --class C. A frozen research-only scope is not a disposition. Drive it now, fire a
session for it and name the pane, file the genuine operator decision (your rung is then ⛔), or drop
it in one line. If any of it stays undriven, line 1 is ❌ Good to close: no — <what remains + who
drives it>."*

### 5.3 Prototype results

Matcher table (measured: `bash /tmp/ca-axis02/proto/run.sh`, 14/14 as expected):

| Expect | Close | Got |
|---|---|---|
| FIRE | the incident close verbatim | FIRE (`the implementation waves in README §5 haven't started…`) |
| pass | `…follow-on: none.` | pass |
| pass | `…follow-on: 1dcc10d88ee3 (the sealed test set, parked on data).` (existing t6a fixture) | pass |
| pass | `…follow-on: README §5 waves are being implemented in pane 472 (fired, pings back).` | pass |
| pass | `…follow-on: ⛔ the timeout raise is your decision (cc-decide 56c6862291f2).` | pass |
| pass | `❌ Good to close: no — the implementation waves … haven't started; I am firing a session` | pass (polarity no) |
| pass | `close_shape_template` output | pass (placeholder) |
| pass | undriven follow-on inside a ``` fence, real `follow-on: none` outside | pass |
| pass | `Follow-on: the two calls below are yours.` | pass (owned ⇒ D1) |
| pass | `Follow-on: the soak, waiting on 24h of data (not-yet-true).` | pass (park) |
| pass | `Follow-on: the Monday call reminder (`health.call-dr-shahinian-949`).` | pass (dotted id) |
| FIRE | `Follow-on: the AM-31 fixture folders don't exist yet.` | FIRE |
| FIRE | `Good to close: yes — follow-on: Waves 1-5 and 7 (agent work, not started).` | FIRE |
| pass | `✅ Complete and landed. Follow-on: waves not started.` (no verdict) | pass |

Full-hook replays on a patched copy (`/tmp/ca-axis02/hookcopy/hooks/completion-assert.sh`, measured
with `HOOK_OVERRIDE=… bash /tmp/ca-axis02/replay.sh`):

| Run | Input | Result |
|---|---|---|
| E | incident, fresh latch | `fired arm:"handoff+followon" class:"followon" 1/2` |
| **F** | **incident, assert pre-capped 3/3 (the live state)** | **`fired arm:"handoff+followon" class:"followon" 1/2`**: reaches the incident |
| G | incident minus line 13 | `fired arm:"followon" class:"followon"` |
| H | `✅ Good to close: yes — …; follow-on: none.` | `abstained ledger-clean` |
| I | `…follow-on: README §5 Waves … in pane 472 (fired; pings back).` | `abstained ledger-clean` |

**Not run:** the full `tests/completion-assert*.bats` suites against the patched copy. `cc-bats`
refused with `REFUSED — 2 concurrent bats execution root(s) … AND 1-min load/core at or above 2.0`
(exit 75), on two attempts about 10 minutes apart. The waiver writes `~/.claude/state/bats-waivers.jsonl`, which this slot may not touch.
Regression status of the existing ~200 tests under the patch is therefore **unverified**. The class
change at step 6 only affects messages with d8=1, which no existing fixture produces as far as I can
tell (estimated by reading: the only YES-with-follow-on fixtures are t6a/t6b at `:2467-2473`, both
exempt). The implementer must run the suites.

### 5.4 Test sketches (tests/completion-assert.bats, reusing `_cvf` `:2379` / `_cvf_txt` `:2376`)

```bash
# fixture: tests/fixtures/close-behavior/incident-2026-10-18.txt  (the 15-line close verbatim)
@test "D8 FIRE: the 2026-10-18 incident close (yes + undriven follow-on) ⇒ followon" {
  _cvf d8inc "$BATS_TEST_DIRNAME/fixtures/close-behavior/incident-2026-10-18.txt"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q "names work nobody is driving"
  printf '%s' "$output" | grep -q "README §5 haven't started"
  grep -q '"class":"followon"' "$COMPLETION_IDL"
}
@test "D8 STARVATION: assert budget spent 3/3 (the live incident state) ⇒ still FIRES, own class" {
  local wt="$BATS_TEST_TMPDIR/wt-d8cap" key
  key="$(printf '%s|%s|%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "cvf-d8cap" "$wt" | shasum | cut -c1-16)"
  mkdir -p "$COMPLETION_STATE_DIR"
  printf '%s\n' "a1 assert" "a2 assert" "a3 assert" > "$COMPLETION_STATE_DIR/$key.fired"
  _cvf d8cap "$BATS_TEST_DIRNAME/fixtures/close-behavior/incident-2026-10-18.txt"
  fired "$output"; grep -q '"class":"followon"' "$COMPLETION_IDL"
}
@test "D8 CONTROLS: none / filed id / fired pane / ⛔ / owned / park / no-verdict ⇒ no followon" {
  for v in 'none.' '1dcc10d88ee3 (the sealed test set, parked on data).' \
           'Waves 1-5 and 7 in pane 472 (fired; pings back).' '⛔ cc-decide 56c6862291f2 (your call).' \
           'the two calls below are yours.' 'the soak, waiting on 24h of data (not-yet-true).'; do
    _cvf "d8c$RANDOM" "$(_cvf_txt "d8c$RANDOM" "✅ Good to close: yes — nothing of mine is open; follow-on: $v" '' '✅ Complete & live on trunk — x.')"
    [ "$status" -eq 0 ]
  done
  if grep -q '"arm":"[^"]*followon' "$COMPLETION_IDL"; then false; fi
}
@test "D8 CONTROL: an honest NO naming the same waves ⇒ no followon (a no is never this arm's)" { … ❌ Good to close: no — … }
@test "D8 MENTION: the template, or the clause inside a fence ⇒ no followon" { … close_shape_template … }
@test "D8 SEAM: CC_CLOSE_FOLLOWON=0 silences; COMPLETION_FOLLOWON_MAX is a hard cap" { … capped:followon:2>=2 … }
@test "D8 ABSTAIN: assignee (AGENT_IDENTITY_LIB stub confirming) and active research program ⇒ no followon" { … }
@test "D8 GENUINE: a close that names a real value fork ('which option do you prefer') ⇒ genuine-blocker, silent" { … }
@test "D8 UNIT: close_followon_undriven table (14 rows of §5.3) incl. the awk -v '\\.' trap row ('Waves 1-5')" { … }
```

## 6. Always-firing risk (census)

A read-only Python pass (`/tmp/ca-axis02/census/census2.py`) covered 1,954 transcripts under
`~/.claude*/projects/*/*.jsonl` modified in the last 14 days. It looked at main-thread assistant
messages containing `good to close`, with polarity replicated from `close_verdict_polarity`
(measured):

- verdict messages 2,289: yes 652, no 1,626, none 11.
- YES with a follow-on clause: 556. Of those, value `none` 319, an id / pane / decision token 164,
  empty 4, prose with no id 69 (54 unique after de-duplicating repeated records).
- Prose class after the owned/park exemptions (`refine2.py`): owned 45, park 1, residual 8. 4 of the 8
  are dotted tracker ids (`health.call-dr-shahinian-949`, `vehicle.call-state-farm-800`), which the
  final `_CS_FO_DRIVEN` exempts.
- **Estimated D8 fire set: 4 of 556 (0.7%).** These are the incident (true positive), `the AM-31
  fixture folders don't exist yet.` (likely true positive), `reply to Ryan by Fri Oct 16.` and `the
  owner's reply.` (personal-assistant waits, mild false positives, each cured by one re-close naming
  the owner, e.g. "yours" or "waiting on the owner").

This is an estimate: the census uses a Python re-implementation of the matcher, not the awk itself.
It is silent when nothing drivable remains (`none`) and silent on ids, panes and ⛔.

Residual risks:
- (a) **Laundering.** A 12-hex token passes on shape alone, so a git sha prefix would launder the
  clause. Optional hardening: check each id against the D1 backlog fold (`_ca_blg_cached`, `:456-466`),
  fail-open.
- (b) **Filing laundering.** Filing the waves with `--why-not-now no-capacity` passes D8 and
  `FILED_MINE` (`:1042`). That is the "a row is not a disposition" hole, and it belongs to the
  ledger/backlog axis.
- (c) **Closes without the label.** A YES that states undriven work outside a `follow-on:` label
  (e.g. in S4 prose) is not covered. An optional variant also matches a not-started tell (`haven't
  started|not started|research only`) on the verdict line itself. The census found that tell in only
  3 prose values, so it adds little.

## 7. Matching rule-text change (no net budget growth)

- `CLAUDE.rules.slim.10-session-close.md:146`: replace *"A qualification goes in S2's `follow-on:`
  clause, beside the assertion."* (13 words) with *"S2's `follow-on:` holds only none, filed ids,
  fired panes or ⛔ decisions; undriven work makes it no."* (17 words). To pay for it, cut from line
  22 the duplicated example *"`✅ Good to close: yes — nothing of mine is open; follow-on: <filed
  ids|none>`"*. The template in `close-shape.sh:179` already carries that example, and D8's block
  reason teaches it at the moment it matters. Net about -5 words (estimated by word count).
- `CLAUDE.global.md:928`: the same one-clause substitution ("anything that would withdraw the
  assertion goes in S2's follow-on: clause") ⇒ "the follow-on clause holds only none / filed ids /
  fired panes / ⛔; anything undriven makes the verdict no". Roughly equal length.

## 8. Secondary fix: give the arm-2 prose arms their own budget

RC3 starves D1/D3/D4/D5 the same way it starved D6 before item 3b464e94b3ff. Proposal: when
`contra=0` and any of d1/d3/d4/d5 fired, claim class `surface` (`COMPLETION_SURFACE_MAX`, default 2)
instead of `assert`. Insert in the class block `:1608-1615` before the final `fi`. This changes which
budget a pure-prose fire draws on; the ledger arm's class, count and reason stay byte-identical.

Evidence it matters: 8 prose-arm suppressions in about 2.5 days of IDL (§2). That is lower value for
this incident than D8, because D1 aimed at the wrong object anyway. Conviction 70%.
