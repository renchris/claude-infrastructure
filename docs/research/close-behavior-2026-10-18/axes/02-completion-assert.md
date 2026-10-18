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

## Skeptic verdicts

Skeptic pass, 2026-10-18. Read-only. I re-ran every claim I could re-run without writing anything: no
scratch files, and pipes only. I did not re-run the hermetic replays, because `replay.sh` does
`rm -rf` and writes under `/tmp`. I read their recorded outputs instead (`/tmp/ca-axis02/run-*/idl.jsonl`, `out.json`).
I did not run bats.

### Root causes

| # | Verdict | Conviction | Why (re-checked evidence) |
|---|---|---|---|
| RC3 (cap starvation) | **confirmed** | 97 | Re-ran `grep 5759497b ~/.claude/autonomy/idl.jsonl \| grep completion-assert`. Fires at 13:18:34, 13:19:02 and 13:19:40Z, each `class:assert` with the identical fact "1 commit(s) YOU wrote are committed-but-unlanded". At 14:27:50Z: `capped:3>=3 suppressed_arm:handoff rung:✅`. I recomputed the latch key `sha(CFG\|SID\|CWD)[:16]` for `~/.claude-secondary`. It is `25fe0af89b86448c`, and its `.fired` file holds exactly 3 `assert` lines, mtime 13:19:40Z (measured: `cat`, `date -r`). Class table at `:1608-1615`: D1/D3/D4/D5 always fall to `assert`. |
| RC1 (nothing reads the follow-on) | **confirmed** | 95 | Re-ran the lib on the extracted close: `close_shape_missing`=`[]`, polarity=`yes`, `close_verdict_not_first`=pass. Greps of the hook's own regexes: `CA_OFFER` 0, `CA_YES_HEDGE` 0, `GENUINE` 0, `CA_HANDOFF` only `13:needs your`. `grep -ni follow.\?on` in the hook and lib finds comments and the template only. Wider than this hook: `dispatch-assert.sh`, built for this defect, also abstained `no-naming-tell` at 14:27:48Z (IDL). |
| RC5 (D1 aims at the wrong object) | **confirmed** | 88 | The `CA_HANDOFF` match is line 13 only (the 70% `settings.json` timeout). The replay-A reason is D1's "File each operator-only step" text (read from `run-A/out.json`). "Would not have driven a wave" is counterfactual. D1's reason does open with "If you can run it, run it now", but it names nothing in §5. |
| RC2 (the contract licenses the pattern) | **weakened** | 65 | The template does **not** license it. `close-shape.sh:179` and slim `:22` restrict the value to `<filed ids…\|none>`, and the incident clause violates that. The licence comes only from slim `:146`, which is 10 words (measured `wc -w`, not 13), plus `CLAUDE.global.md:928`. **`:928` was not resident in the incident session.** `~/.claude-secondary/CLAUDE.md` symlinks to `~/.claude/CLAUDE.md`, the slim variant (`install.sh:1047-1054`), and `grep -c 'withdraw the assertion goes in'` on it returns 0. So the contract contradicts itself rather than licensing the pattern, and no measurement shows that `:146` caused the wording. |
| RC4 (ledger terms are git/store facts only) | **weakened** | 80 | Right in substance: a research doc is invisible. Imprecise in one detail: `REMAINDER` counts unchecked `- [ ]` boxes in the frozen-DoD capture (`wrap-ledger.sh:924-931`), which is a text artifact the session writes. It read 0 because the scope was frozen as research only and the §5 waves never became DoD boxes. That is an existing seam the axis did not consider (see Missed). |
| RC-early (earlier instances never reach this hook) | **confirmed** | 85 | The gz IDL shows `no-close-tell` at 05:59:29, 06:04:16 and 06:08:11Z for sid 5759497b. The "What I'd do, in order" reply (step 1 "over 90% sure") is in `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-….jsonl.handed-off`, in the 06:00-06:05Z window. |

### Fix candidates

**D8 `followon` — weakened, 50.** It is implementable at the cited points. I checked every line:
`close-shape.sh:161/163/311`, `completion-assert.sh:1541/1543/1546-1547/1601/1612/1654`, with
`_ca_assignee` at `:657`, `_ca_source_close_shape` at `:918` and `_ca_rp_active` at `:1324`, all
defined above the insertion point. By reading, no existing fixture should flip: every `follow-on:`
fixture in `tests/completion-assert*.bats` is `none`, an id, a `<placeholder>`, or has no verdict
(grep). Re-running `proto/run.sh` gives 14/14 ok. But the matcher as specified breaks four of the
brief's constraints.

1. **The firing estimate is not an estimate of this matcher.** `refine2.py`'s OWNER regex adds
   `pane|session|decisions?|below|above|tracked|owns`, and the proposed `_CS_FO_OWNED` has none of them.
   `census2.py`'s id class also adds `packet|fired|firing|pane(s)`. I ran the **real prototype awk** on the 54
   unique prose values in `census/out2.txt`. **14 fire, not 4** (measured). The 40 sampled id-class
   values fire 0. I then mapped each of the 14 to its own Stop record (jq over `idl.jsonl.2026101*.gz` + `idl.jsonl`):
   - 3 were gated off by contra=1, including 2 of the axis's named 4. Ryan (`e7659abe`) sat at 🔧, the owner's reply (`e7ed8439`) at 🔧, and `2328e32b` at ⛔.
   - 4 were reachable at contra=0. One is the incident (✅). The other three:
     - `f7351f3b` 10-16T23:51 at **👤**: "one test after the next reboot, below."
     - `f7351f3b` 10-15T15:46 at ledger-clean: "two steps that need you, plus one decision (below)."
     - `b18a0aed` 10-17T21:06 at ledger-clean: "the migration-corpus fixes go to a dedicated session the program lead fires before W1".
   - 7 fall outside the retained IDL window. One is AM-31, a likely true positive. The others include "approve the three build items below when you're ready.", "the backlog rows below", "…is now tracked." and "the heartbeat-fix session (window 37) is still working".

   Hand-read precision is about 2/14. **That includes blocking genuine operator steps and decisions at 👤**, which the brief forbids.
2. **Its own cure re-fires, and so do honest nothing-drivable closes** (measured on the prototype):
   - `follow-on: dropped the 70% timeout raise, not worth filing.` ⇒ FIRE, although D8's reason says "drop it in one line".
   - `…the live layer catches up within its normal window.` ⇒ FIRE.
   - `…the nightly launchd job applies it automatically.` ⇒ FIRE.
   - `…Wave 1 is being driven by the session I fired (window 37).` ⇒ FIRE.

   The cap of 2 bounds the damage, but these are fires where nothing drivable remains.
3. **Mention vs use.** The matcher reads `$MSG`, not `MSG_UNQ`. A YES close with no follow-on on its verdict line
   that later quotes the incident's clause in backticks or "quotes" ⇒ FIRE (measured, both forms). That is the
   documented FP class at `completion-assert.sh:425-438` ("this hook firing on the very close that shipped
   it"). This research program's own closes, and the D8 implementer's, will quote that clause. The
   "D8 MENTION" test sketch covers only the template and fences.
4. **The owned/park lists are a spelling denylist, and they leak in both directions** (measured, all pass):
   - Owner phrasings: "…the operator's to prioritise", "your call when to start", "goes to a later session".
   - Park and id phrasings: any 12-hex git-sha prefix, "blocked on nothing but time", "waiting for a free slot".
   - Label variants: `Follow-ups:`, `Follow-on —` (no colon), `Next:`.
   - Lead-token false exemptions:
     - `none yet, the waves in §5 still need doing` and `n/a beyond the §5 waves…` pass on the `none`/`n/a` lead.
     - `zero-downtime migration … (not started)` passes on `zero` in `_CS_FO_NONE`.
     - `the operator-readout fix in §5 (Wave 3, not started)` passes on `operator` in `_CS_FO_OWNED`. This repo's own hook names (`operator-readout`, `OPERATOR ▸`) trip it.

   The axis says "owned is D1's territory; D1 already checks the store". That is false for most of the list:
   `CA_HANDOFF` (`:467`) has no bare `your`, `operator`, `for you` (only `for you to (run|do)`), `the lead`,
   `goes to` or `owned by`, so those phrasings pass both arms. The repo's standing non-actions already rank
   this shape: `docs/research/exhaustive-drive-2026-09-08/SYNTHESIS.md:139-141` says "Do **not** widen
   dispatch-assert NAME_TELL (85; a denylist of spellings)" and "do **not** build a prose detector for the
   un-filed … close (90; … never detect it)". The axis does not engage with either.
5. **The cheapest compliance is a relabel, not a drive.** `❌ Good to close: no — the §5 waves haven't started`
   passes D8 (polarity no) and every other arm. D6 `verdict-first` needs a done-reading line 1, and D4
   needs an offer phrase. So D8 can fix the verdict's honesty, but not the operator's actual loss
   ("no net positive if research is done but its not enacted on").
6. **It drops D6's stated gates.** It has no origin gate and no positive-write gate, so it fires on
   fired-peer notify-back pings and on write-free sessions, which D6 exempts by policy (`:1411-1415`).
7. **It would be a second follow-on matcher.** `scripts/drain-peer-findings.py:92-110` already parses S2's
   ledger (`_FOLLOW_ON`, `_NIL`, `_NIL_LEAD`, `MIN_CLAUSE`=40). `close-shape.sh:15-20` warns that two copies of a load-bearing matcher drift apart.

A variant I would rate about 70: match only the `follow-on:` on the verdict line itself, on the
quote-stripped view; limit RUNG to ✅ (dropping 👤 removes the measured operator-step FP, and the incident
was ✅); exempt `dropped`; and replace the owned/park spelling lists with a store fact, namely any
backlog row, registry fire or cc-decide packet this session wrote. That is `dispatch-assert.sh`'s
mechanical discharge (`:26-31`), so that, in that hook's own words, "gaming the hook IS compliance".

**Template and rule text — weakened, 55.** Not always-firing (text only). The template edit is safe: only
`close_shape_ok` rejection pins it (`tests/completion-assert.bats:1657`), and the kept `<…>` holds that.
The budget arithmetic is off:
- The current `:146` sentence is 10 words; the replacement is 17, so +7 (measured `wc -w`).
- The proposed `:22` cut leaves that bullet ungrammatical ("line 1 … or `❌ …`").
- `:22` already says `<filed ids|none>`, so the defect is the contradicting `:146` sentence. Deleting it outright is −10 words and needs no new text.
- The `CLAUDE.global.md:928` swap has no runtime effect under the default slim variant (see RC2).

**`surface` cap class for D1/D3/D4/D5 — weakened, 40.**
- **The existing suite contradicts it.** The test "D7 CLASS: a message that also fires D1 keeps class=assert" (`tests/completion-assert.bats:1894-1906`) runs under `CA_YOURS_LEDGER` (`:1750`: every contra term 0, RUNG=👤) and asserts `"class":"assert"`. This fix turns it red. That test's comment (`:1891-1893`) states the no-disturbance principle this fix reverses.
- **The benefit is overstated.** Of the 8 prose-arm suppressions, 5 are `ledger+handoff`, i.e. contra=1, and the fix leaves those in `assert`. Only 3 had contra=0, and one of them is the incident, where D1 aims at the wrong object. Measured: the jq tally reproduces 4,065 records, 181 `false-done` fires and 344 `capped:assert`.
- **An unconsidered alternative.** In **19 of 30** sessions that spent 3 or more fact-bearing `assert` fires, at least 3 were on one identical facts string (measured jq, IDL 10-16..10-18). The incident's three 📦 fires came 66 s apart on the same fact. Latching ledger convictions per fact would have left 2 slots with no new class. Whether repeating a conviction is itself useful is unmeasured.

**Id hardening against `_ca_blg_cached` — refuted, 15.** D1 calls that cache only with
`--blocked --json` (`:492-498`), so the fold holds blocked rows only. Correctly filed open agent rows
(`add --why-not-now`), done rows and cc-decide packet ids are all absent, so the hardening would fire D8
on legitimate ids. Fail-open covers read errors, not absence. A correct oracle needs an all-status fold
(the 10 MB, 2.1-2.8 s read that `:416-423` moved off the hot path) plus a decisions read.

### Measurements

| Item | Verdict | Note |
|---|---|---|
| IDL incident record `capped:3>=3` | confirmed | re-ran grep; latch file read directly |
| Replays A-D | confirmed | read `run-A..D/idl.jsonl`; not re-run (`replay.sh` writes) |
| Lib calls and greps on the close | confirmed | re-ran |
| jq tally of 4,065 records | confirmed | re-ran: same counts to 20:22:59Z; suppressions 📦 245, 🔧 77+3, ⛔ 14+2, ✅ handoff 2, 👤 handoff+act 1 |
| Census 2,289 / 652 / 556 | weakened | not re-run; its classes are `census2.py`'s regexes, not the proposed matcher's |
| "D8 fires on 4 of 556 (0.7%)" | **refuted** | the real awk fires on 14 of 54 unique prose values; `refine2.py`'s OWNER regex is wider than `_CS_FO_OWNED` |
| Prototype 14/14 | confirmed | re-ran; the table has no owned-leak, quote, `dropped` or nothing-drivable rows, which are the cases that fail |
| Patched replays E-I | confirmed | read outputs |
| Bats not run | confirmed | I did not run them either. By reading, D8 flips no fixture and the `surface` class flips `:1894` |
| `diff -q` rule copy | confirmed | re-ran: IDENTICAL |

### Missed by the axis

1. `hooks/dispatch-assert.sh` sits in the same Stop chain and was built for exactly this defect (header `:2-31`). It abstained `no-naming-tell` at 14:27:48Z. Its record-written-since-turn-start discharge is a better "driven" oracle than D8's spelling lists. Axis 08 covers it; this axis does not cross-reference it.
2. `scripts/drain-peer-findings.py` is a working follow-on-clause parser and prior art. D8 would be a second, divergent one.
3. The standing non-actions at `SYNTHESIS.md:139-141` (spelling denylists and prose detectors for the un-filed close).
4. Budget burn on one repeated fact (19/30 sessions). The incident's 3 slots went in 66 s on one unchanged fact.
5. The cheapest D8 cure is a ❌ relabel that drives nothing. Nothing downstream turns a ❌ verdict into continuation.
6. `CLAUDE.global.md:928` was not loaded in the incident session; only slim `:146` was.
7. The DoD seam: writing the §5 waves as `- [ ]` items under `Scope (grown):` makes `REMAINDER`>0, hence contra=1 and 🔧, with no new arm. The frozen "research only" line is what held it at 0.
8. D8 has no origin or positive-write gate, unlike D6.
9. D8 reads `$MSG`, not `MSG_UNQ`, so a quoted mention of the incident clause fires it.
