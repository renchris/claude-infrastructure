# A07 — Caps, latches, exemptions and kill-switch false positives

Wave: exhaustive-drive 2026-09-08. Read-only. Every number below carries its command and its
population. "Measured" = I ran it. "Inferred" = I did not.

---

## Answer first

**The caps are not the leak — three other things are, and they all fail in the silent direction.**

1. **The one cap the operator can read in `CLAUDE.md` is the only one that does not bind.**
   `CLAUDE_CONTINUE_MAX` (default 8) fired **0 times in 11 days of IDL** because the block message
   instructs the model to re-arm and a re-arm zeroes the counter. Measured chains of **311, 236, 220,
   206, 153** consecutive Stop-hook blocks exist in the 30-day corpus, 307/311 of them `continuation`.
   Meanwhile the arms that *verify* the close **do** hit their caps: in every one of those long chains
   completion-assert appears at most **3** times (= `COMPLETION_MAX`) and anti-deference at most **1**.
   The checker goes quiet after 3; the driver never stops. That is the polarity backwards.

2. **The kill switch fires on ordinary briefs, and on a dispatched session the false positive is
   permanent, not one-shot.** `last_user_msg()` correctly skips `isMeta=true` records — and hook block
   feedback IS `isMeta=true` (620/630 measured today) — so in a fire-and-forget session the "last
   genuine user message" stays **the brief, forever**. Measured over 6,131 transcripts / 30 d:
   **140 sessions carry a kill phrase in their last genuine user message**, 125 of them single-message
   dispatched sessions, and **100 of the 140 wrote files**. In a hand-read of 40 sampled hits, **32
   (80%) are not stop orders**; 4 (10%) are. One measured brief that trips it reads
   *"drive to completion, commit as you go, re-arm /goal if it is not active, **and stop** only on a
   genuine credential or destructive-migration…"* — the sentence that demands maximum autonomy
   disarms the autonomy machinery.

3. **The attribution oracle is blind to the editing mode auto-mode prescribes.**
   `hooks/lib/session-writes.sh:143` matches `^(Write|Edit|MultiEdit|NotebookEdit)$`. Measured over
   481 transcripts touched in the last 24 h: **20,879 Bash tool calls vs 368 file-edit tool calls**,
   and of the 260 sessions that wrote files at all, **229 (88.1%) wrote only through Bash**. Those
   sessions get no mechanical 🔧 arm and no ship floor, for their whole life, silently.

Everything else on this axis (`ANTIDEF_MAX`, `DISPATCH_ASSERT_MAX(_TOTAL)`, `CC_MECH_MAX`,
`CC_SHIP_FLOOR_MAX`, `CC_WAKE_FLOOR_MAX`, boundary-handoff's latch, operator-readout's TTL) is
either never reached or reached at rates that do not matter. The exemptions are narrower and
better-engineered than expected.

---

## §1 The cap and latch inventory, with defaults and measured trip counts

Defaults read from source; trip counts measured over the reconstructed **11-day IDL**
(2026-08-29 → 2026-09-08, 58,950 hook records — see §1.1, this corrects the wave brief's
"13-hour census").

| Mechanism | Var / default | Where | Scope of the counter | Trips, 11 d | Denominator |
|---|---|---|---|---|---|
| anti-deference cap | `ANTIDEF_MAX` **3** | `anti-deference-nudge.sh:59,350` | per session, counts FIRES | **0** | 1,982 evals |
| anti-deference latch | msg-hash set | `:342-346` | per session, per message hash | **1** | " |
| dispatch re-check cap | `DISPATCH_ASSERT_MAX` **2** | `dispatch-assert.sh:54,218` | per pending obligation | **0** | 1,993 evals |
| dispatch session cap | `DISPATCH_ASSERT_MAX_TOTAL` **6** | `:55,247` | per session | **0** | " |
| completion `assert` cap | `COMPLETION_MAX` **3** | `completion-assert.sh:105,1064` | per session, per class | **41** | 1,694 evals |
| completion `shape` cap | `COMPLETION_SHAPE_MAX` **2** | `:1065` | per session | **0** | " |
| completion `act` cap | `COMPLETION_ACT_MAX` **2** | `:1068` | per session | **0** | " |
| completion latch | msg-hash set | `:1039,1071` | per session, per message hash | **14** | " |
| continuation cap | `CLAUDE_CONTINUE_MAX` **8** | `session-continue.sh:1117` | per sentinel, **zeroed by `set`** | **0** | 1,182 records |
| mechanical 🔧 budget | `CC_MECH_MAX` **2** | `:921` | per (sid, cwd), survives `clear` | **10** | " |
| ship floor budget | `CC_SHIP_FLOOR_MAX` **2** | `:1030` | per session | **15** | " |
| ship floor latch | HEAD-sha | `:1041` | per (sid, HEAD) | **14** | " |
| wake floor budget | `CC_WAKE_FLOOR_MAX` **2** | `:689` | per session | **0** | " |
| wake floor TTL | `CC_WAKE_FLOOR_TTL_S` **600** | `:690` | per session | **0** | " |
| boundary-handoff latch | hash(cfg\|cwd)-HEAD, re-arms on +10 pct fill or +10 MB tx | `boundary-handoff.sh:478-497` | per (cfg, cwd, HEAD) | **92** | 1,919 evals |
| operator-readout TTL latch | `CC_OPREADOUT_TTL_S` **900** | `operator-readout.sh:316,1383-1395` | per (cfg, sid, cwd) + content stamp | **376** | 1,103 evals |
| **harness** consecutive-block cap | `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` **8** | binary, see §2 | per query loop; resets on a new user turn | **0 observable** | see §2 |

Commands:

```bash
# reconstruct the 11-day IDL (the live file alone is 13 h)
cat ~/.claude/autonomy/idl.jsonl; for g in ~/.claude/autonomy/idl.jsonl.*.gz; do gzcat "$g"; done > idl-all.jsonl
jq -rc 'select(.hook!=null)|[.hook,.disposition,(.reason//"-")]|@tsv' idl-all.jsonl \
  | grep -E 'capp|latch|budget|assignee|teardown|kill-switch|not-mine' | sort | uniq -c | sort -rn
```

### §1.1 The IDL is 11 days, not 13 hours — correction to the wave brief

`~/.claude/autonomy/` holds rotated archives `idl.jsonl.<ts>.gz` and `idl.jsonl.chain.<ts>.gz` back to
2026-09-01, and the oldest records inside reach **2026-08-29**. Reconstructed: 1,863,601 lines,
58,950 with a `.hook` field. Per-day: 966 / 451 / 2,566 / 2,404 / 3,160 / 6,697 / 9,076 / 6,081 /
14,533 / 1,263 / 11,753 (Aug-29 → Sep-08). Every other axis in this wave that was told "13 hours"
can have 11 days for one `gzcat`.

### §1.2 Two source-level nits found while enumerating

- **`CC_MECH_MAX` has two different literal defaults.** `session-continue.sh:149` (`clear`) writes
  `${CC_MECH_MAX:-3}` into the `.mech` sidecar; `:921` (the reader) uses `${CC_MECH_MAX:-2}`. Harmless
  today because `clear`'s intent is to spend the budget outright and `3 >= 2` does that — but the `3`
  is the *old* default the header at `:916` explicitly says was lowered, left behind. Cosmetic; fix
  by writing the reader's own `$mmax`.
- **A capped abstain records nothing about what it suppressed.** `completion-assert.sh:1079` logs
  `capped:3>=3` with no `arm`, `rung` or `facts` — while a *fired* record carries all three. All 41
  cap trips are therefore unsighted: we can count them and cannot say what went unsaid. Same for
  `anti-deference-nudge.sh:350`.
- **`ENABLE_STOP_REVIEW="0"` in `~/.claude/settings.json` env names nothing in the binary.** Measured:
  `LC_ALL=C grep -a -c` for `ENABLE_STOP_REVIEW`, `STOP_REVIEW`, `stopReview` in
  `~/.claude-260/.../claude.exe` → **0, 0, 0**. A dead knob.

---

## §2 The harness cap, read out of the 2.1.260 binary

```js
let Vd = a.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8;
if (Vd > 0 && qd > Vd) return i("tengu_stop_hook_block_count",
    {count:qd, is_subagent:…, hit_max_turns:!1, hit_cap:!0, goal_active:zf}),
  yield kt(`A hook blocked the turn from ending ${qd} consecutive times — overriding and ending turn. `
    + "For Stop/SubagentStop hooks, check stop_hook_active in the input and return success while it's "
    + "true. Set CLAUDE_CODE_STOP_HOOK_BLOCK_CAP to raise this limit.", "warning"),
  yield* ex(Et,[...kr,...Ts],{stopHookActive:No}), {reason:"completed"};
```

Extracted at byte offset 164402088 with a bounded `python3` `bytes.find` window (a
`grep -o '.{0,120}…'` over the 198 MB binary does not finish in 120 s — use `find`, not a regex).
Four facts that matter:

- **`qd = go + 1`, incremented once per Stop that had ANY blocking error** (`let Ac=Nr+1, qd=go+1`
  inside `if(dm.blockingErrors.length>0)`). So a same-Stop double-block — session-continue plus
  completion-assert, measured at 2.5% of Stops in `session-continue.sh:197-201` — costs **one** unit,
  not two. A plausible worry, refuted.
- **`Vd > 0` guards the comparison, so `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0` means UNBOUNDED**, not
  "never block". And because it is `??` (nullish), an empty-string value also disables it
  (`"" > 0` is false). Anyone tuning this should know `0` is the off switch for the *cap*, not the
  hook.
- **The trip is `qd > Vd`, strictly greater** — 8 consecutive blocks are allowed; the 9th overrides.
- **The counter is per query-loop and resets on a genuine new user turn** (`stopHookBlockingCount:0`
  in every retry transition). *The harness already implements the re-arm semantics §5 recommends;
  our per-session counters do not.*

**The override leaves no trace.** Searching all 6,131 transcripts / 7.27 GB for
`A hook blocked the turn from ending` returns **0 hits** — it is a `kt(…,"warning")` UI notification,
not a transcript record. So "how often does the harness cap release a session into idle?" is
**not answerable from disk**; the only local signal is the `tengu_stop_hook_block_count` telemetry
event, which is not written locally. Upper bound from my own chain measurement: **44** chains of ≥8
consecutive blocks in 30 days (§3).

---

## §3 Block-chain lengths — the measurement that inverts the story

Population: 6,131 transcripts, 30 days, 7.27 GB. A "chain" = consecutive `type:"user"` records whose
text starts `Stop hook feedback:`, terminated by any genuine (non-`isMeta`) user record.

```
transcripts with >=1 Stop-hook block: 568
total Stop-hook block records:        4085
chain-length histogram:
  1:818  2:254  3:92  4:51  5:12  6:12  7:6  8:3  9:3  10:2  11:1  12:7  13:3  15:4
  18:1 19:1 20:1 21:1 22:1 23:2 24:1 28:1 29:1 36:1 72:1 79:1 84:1 93:1 123:1
  153:1 206:1 220:1 236:1 311:1
chains reaching >=8 (harness cap zone): 44
harness override messages found:        0
```

Composition of the ten longest chains (counting which hook's text appears in each block):

| chain len | continuation | completion-assert | anti-deference | wake floor | ship floor |
|---|---|---|---|---|---|
| 311 | 307 | **3** | – | 1 | – |
| 236 | 233 | **3** | – | – | – |
| 220 | 220 | – | – | – | – |
| 206 | 101 | **2** | 1 | 1 | – |
| 153 | 147 | **3** | 1 | – | 1 |
| 123 | – | **3** | 1 | – | – |
| 93 | 93 | – | – | – | – |
| 84 | – | **3** | – | 1 | – |
| 72 | 72 | – | – | – | – |
| 36 | 36 | – | – | – | – |

`completion-assert` never exceeds 3 — it is *exactly* `COMPLETION_MAX`, spent in the first handful of
blocks of a chain that then runs for hundreds more. This is the whole finding in one table.

**Why the continuation cap never binds.** `session-continue.sh:117` — the CLI `set` path — does
`rm -f "${f}.count"`, and the block message at `:1149` tells the model in so many words:
*"Re-arm each 🔧 turn … a fresh `set` refreshes the step AND resets the continuation counter — this is
how a long grind stays under the ${MAX}-cap."* Measured on the live IDL: of 357 `fired continue`
records over 11 days, **353 are at `count:1`**, 3 at 2, 1 at 3; and one real session
(`b0bf12dc-…`, traced turn-by-turn) fired 10 continuations in 29 minutes with `armed cli-set`
interleaved and never passed depth 3. This is the codebase's own
`bounded-gate-unbounded-by-compliance` lesson: the mechanical arm's header at `:900-916` documents
the exact trap and defends `.mech` against it; the CLI arm keeps the reset as a feature.

**Failure direction:** toward never releasing. For this wave's goal that is the *preferred* side —
but the operator's resident `CLAUDE.md` says "a hard cap (`CLAUDE_CONTINUE_MAX`, default 8) bounds
runaway", and measured, the largest observed run is 311. The sentence is false for the agent-armed
path and should say so.

### The 41 completion-assert cap trips

All 41 are class `assert` at `capped:3>=3`; zero `shape`, zero `act`. Twelve distinct sessions:
`dfe3a4d4` ×8, `6fb3198c` ×8 (+1 the following day), `4cc024cd` ×8, `41aaaa07` ×5, `88a12591` ×3,
`94d58849` ×3, and six singletons. Read as suppressed closes: **29 of the 41** are closes *after* the
cap was already spent — closes where the arm had a tell and said nothing.

Hand-read of `41aaaa07` (main session, `wt-pool-7`, 01:31 → 11:35, transcript 2.3 MB): its closes are
high quality — verdict on line 2, rung glyph on line 1, content-verified shas. So the five cap trips
there suppressed checks on a session that did not need them; the cap did no harm *in that case*. The
structural problem is the denominator: **301 real sessions produced 1,648 completion-assert
evaluations over 11 days (mean 5.5); 72 sessions (23.9%) had ≥4 evaluations and 15 had ≥20.** A
session with 20+ closes gets 3 conviction checks for its whole life, and `6fb3198c` spent its budget
on 2026-09-05 and was still silent on 2026-09-06 — the counter is per *session*, and a lead session
outlives its budget by hours or days.

---

## §4 Kill switch — the phrase list, the false-positive rate, and why it is permanent

The predicate (`session-continue.sh:224`, hoisted so the wake floor and ship floor share it):

```
KILL_RE='(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[:alnum:]])stop here([^[:alnum:]]|$)|come back to this|^[[:space:]]*(stop|halt)[[:space:].!]*$'
```

Consumers: `session-continue.sh:1090` (armed path — clears the sentinel), `:825` (mechanical 🔧 arm),
`:969` (ship floor), `:734` (wake floor), and `completion-assert.sh` (19 `kill-switch` abstains in
11 days).

### 4a. Census over 30 days / 6,131 transcripts

```
total non-tool_result user records:                 20,521
isMeta=true (injected command/skill/hook bodies):    7,374   of which kill-phrase: 442
genuine (isMeta != true):                           13,147
genuine kill-phrase hits:                              179   (1.36%)
  and [then] stop 160 · stop here 10 · just do X 8 · come back to this 1
```

The `isMeta` guard added in `299e4d563`/`9cab1f800` is load-bearing and correct: it suppresses **442**
would-be disarms, and hook block feedback is itself `isMeta=true` (measured today: 620 of 630
block-shaped user records).

### 4b. Two lexical defects, measured

Splitting every `and [then] stop` match in the corpus by what follows it:

```
and[ then] stop -> TERMINAL (sentence or message end):        87
and[ then] stop -> followed by a WORD:                        88   (50.3%)
just do not / just don't (a PROHIBITION, read as the switch):  3
just do <other word>:                                         10
```

The regex accepts any non-alphanumeric after `stop`, so a *space* qualifies. Measured non-terminal
matches, verbatim:

- `"drive to completion, commit as you go, re-arm /goal if it is not active, and stop only on a
  genuine credential or destructive-migration…"` — the maximum-autonomy brief, disarming autonomy.
- `"RUN THE LAND AS A SINGLE BACKGROUND Bash-tool JOB, and stop expecting auto-background."`
- `"Either do it or say why, and stop re-deriving the premise."`
- `"START at 301 and STOP at 620."`
- `"…and stop dev servers when idle"`, `"…and stop leaning on it"`, `"…and stop calling CloudWatch
  corroboration"`, `"…and stop the bridge writing schema-invalid rows"`.
- `just do not present it as drain`, `Just do not let it stand as the hero class`,
  `just do not quote 5 miles to anyone` — three prohibitions matched as `just do n`.

### 4c. Hand-read, n = 40 (every 4th hit of the 179, chronologically sorted)

| Class | Count | Examples |
|---|---|---|
| **Not a stop order** | **32 (80%)** | fire/recycle/teammate briefs; `"STOP HERE."` as a section marker in reference material; `"and stop <verb>"`; `"just do not …"` |
| Scoped stop (a per-task budget, not "end the session") | 4 (10%) | `"Answer exactly these questions and stop — do not propose an implementation plan"`; `"If you cannot see a live rate in 4 fetches, return UNKNOWN and stop."` |
| Genuine stop order | **4 (10%)** | `"Save what you need to save, I'll come back to this."`; `"stop work, and stop running suites"`; `"reply DONE and stop."`; `"Count to 2 and stop."` |

Four of the 32 are the **24/7 backlog drain chain** (recycles #149, #161, #163, #164) — the fleet's
longest-running autonomous writer, whose regenerated brief contains
`"and stop expecting auto-background"`. Every recycle in that chain inherits the disarm.

### 4d. Why the false positive is permanent, not one-shot

`session-continue.sh:277-283` reasons: *"Bias to DETECT: a false positive merely allows one stop the
model re-arms on its next 🔧 turn."* **That is true for an interactive session and false for a
dispatched one.** `last_user_msg()` re-reads the transcript at every Stop and returns the last
`isMeta != true` user record. In a fire-and-forget session there is only ever one such record — the
brief — because hook blocks are `isMeta=true` and are correctly skipped. So the predicate returns the
same answer at Stop 1 and at Stop 300.

Measured:

```
transcripts scanned:                                                       6,131
with >=1 genuine user msg:                                                 5,882
FIRST genuine msg carries a kill phrase:                                     154
LAST  genuine msg carries a kill phrase  (=> ACTIVE at every later Stop):    140
sessions whose only genuine msg is ONE message (fire-and-forget shape):     4,959  (84.3%)
   ...of those, permanently disarmed from turn 1:                             125
of the 140, sessions that WROTE FILES (Edit/Write or a Bash write idiom):     100
```

**100 writer sessions in 30 days ran with the mechanical 🔧 arm, both floors, the continuation
actuator and completion-assert's check all switched off for their entire lives** — including
`119bfbea` ("Ship the Studio 60 tenant… two weeks late"), `e5d3628d` (claude-infrastructure), and
`d52111aa`.

---

## §5 Exemptions — narrower than expected, with one instrumentation hole

11-day counts:

| Exemption | Hook | Count | Mechanism | Verdict |
|---|---|---|---|---|
| `ship-floor-not-mine` | session-continue | **90** | attribution refused (`session_unlanded_mine` / `session_writes_paths` rc≠0) | the real leak — see §6 |
| `mechanical-assignee` | session-continue | 38 | `agent_assignee_argv` + `agent_team_member_confirms` rc 0 **or 2** | rc 2 exempts on ignorance; **not recorded** |
| `ship-floor-assignee` | session-continue | 32 | same, rc recorded | 30 rc 0, **1 rc 2** — 3% fail-open |
| `team-assignee` | dispatch-assert / operator-readout / boundary-handoff | 80 each | `agent_is_assignee` | consistent across 3 hooks |
| `kill-switch` | completion-assert | 19 | shared predicate | see §4 |
| `teardown` | session-continue (3 arms) | 9 | `wf_teardown_marked` | correct |
| `wake-floor-headless` | session-continue | 0 (11 d) | pane-id `hdl-<hex>` shape | correct, and emits an advisory rather than silence |
| origin close contract (D6) | completion-assert | n/a | `oi_origin_class != origin` ⇒ skip | by design; see §5.2 |

**5.1 `agent_assignee_argv` is NOT the `pgrep -f` trap.** It walks the hook's own `$$` ancestry
(≤8 hops) through `ps -axo pid=,ppid=,command=` and demands cross-field consistency between
`--agent-id` / `--agent-name` / `--team-name`, precisely because a brief that merely *discusses*
teammate argv satisfies co-presence (`hooks/lib/agent-identity.sh:46-63`). Already hardened.

**5.2 Are dispatched sessions under-protected by construction? Partly, and not where you'd guess.**
A fired peer is exempt from the D6 close-shape contract and the D7 act arm only — the conviction and
false-done arms still apply, and there are **zero** `team-assignee` abstains in completion-assert's
11-day census, confirming it. So the *designed* exemptions are tight. The under-protection is
**accidental**, and it is §4d: 84.3% of the fleet's transcripts are single-genuine-message sessions,
which is exactly the shape that turns a one-turn kill-switch false positive into a life sentence.

**5.3 The one hole:** `mechanical-assignee` (38 events) logs no `confirm_rc`, and the arm exempts on
rc 2 (*cannot tell*) as well as rc 0. So 38 sessions were released from the mechanical 🔧 arm and we
cannot say how many were released on ignorance. One `jq` field would close it.

---

## §6 The finding that is bigger than any cap: the attribution oracle vs auto-mode

`hooks/lib/session-writes.sh:143` selects `select(.name|test("^(Write|Edit|MultiEdit|NotebookEdit)$"))`.
Its own header at `:40,:57` names the gap and calls the residue safe: *"A file written ONLY through
Bash (`sed -i`, a heredoc, `git checkout`) is invisible here… The residue fails in the SAFE
direction."*

Two measurements say the residue is now the main case, and that "safe" is the wrong polarity for
this wave:

1. **Auto mode instructs the model to Bash-edit.** The live auto-mode system reminder (present in this
   very session) reads: *"Do your work through the Bash tool wherever it can accomplish the job… make
   file changes with `sed`, heredocs, or short scripts, rather than using the dedicated Read, Edit, or
   Write tools."* `~/.claude/settings.json` has `defaultMode: auto`.

2. **The fleet complies.** Measured over 481 transcripts touched in the last 24 h (452 MB):

   ```
   tool_use census:  Bash 20,879 · WebSearch 1,273 · WebFetch 1,258 · ToolSearch 368
                     Edit 289 · Read 223 · Write 79 · Agent 72 …
   per-session classification (Bash write idiom = sed -i | tee | heredoc | redirect to a code/doc ext):
     edit-tool only :   4
     bash-write only: 229   <-- session_writes_paths returns rc 1 "none"
     both           :  27
     neither        : 221   (read-only / research)
   ```

   Of the **260** sessions that wrote anything, **229 (88.1%)** are invisible to the oracle.

Consequence, by construction: for those sessions the **mechanical 🔧 arm never arms**
(`session-continue.sh:890-893` returns 1 when `session_dirty_mine` is empty) and the **ship floor's
🚀 branch abstains** (`:1022-1023`) — which is `ship-floor-not-mine`, the single largest exemption in
the census at 90 events. Both are *silences*, both are indistinguishable from "nothing was wrong",
and both hit the session shape the operator's own goal is about.

Caveat, stated honestly: my Bash-write regex is a heuristic and over-counts scratch writes to `/tmp`.
The mechanical arm additionally intersects attributed paths with `git status`, so a `/tmp` write would
not have armed it anyway — meaning the 229 is an upper bound on *sessions at risk*, not a count of
*sessions that actually went idle dirty*. The direction is not in doubt; the magnitude is.

---

## §7 Adversarial pass — three things I assumed, then checked

**(i) "Hook timeouts are the silent cap."** Half right. Measured on the largest transcript in the
corpus (240 MB, `4101dbdf…`), a synthetic Stop payload, this box:

| hook | wall time | settings timeout | outcome |
|---|---|---|---|
| `session-continue` | **8.63 s** | 5 s | killed — writes nothing, blocks nothing, logs nothing |
| `completion-assert` | **7.36 s** | 5 s | killed |
| `dispatch-assert` | **13.85 s** | 10 s | killed |
| `anti-deference-nudge` | 4.19 s | 5 s | marginal; exceeds under load |

A killed hook is a **release into idle with work left that no cap, no latch and no IDL record can
see** — strictly worse than any cap in this report. **But it does not explain today's gap.** Testing
the obvious hypothesis: sessions with completion-assert IDL records today have median 1.3 MB / p90
3.5 MB; sessions *without* have median 1.1 MB / p90 3.0 MB — **no separation, and zero transcripts
today exceeded 25 MB**. Fleet-wide exposure is small: of 6,131 transcripts in 30 days, **29 (0.47%)
exceed 25 MB, 7 exceed 69 MB, 2 exceed 150 MB**, and the two largest belong to one non-code project.
So: real mechanism, latent risk, **not** the cause of the lead's 901-closes-vs-469-evaluations gap.
That gap remains unexplained by this axis.

**(ii) "A same-Stop double-block burns the harness budget twice."** Refuted from the binary: `qd=go+1`
increments once per Stop with any blocking error (§2).

**(iii) "The assignee exemption is a `pgrep -f` false positive waiting to happen."** Refuted from
source: it is an ancestry walk with cross-field consistency, already hardened against exactly that
(§5.1). The residual is rc 2 fail-open, measured at 1 of 32 on the ship floor and unmeasurable on the
mechanical arm.

---

## §8 Recommendations, with failure direction

Ordered by conviction. Every one states which way it errs.

**R1 — Make the kill-switch terminal-only, and exclude a session's own brief. (conviction 92%,
effort S)**
Two edits to `KILL_RE` in `hooks/session-continue.sh:224`: require terminal context after `stop`
(`and( then)? stop[[:space:]]*[.!;]?[[:space:]]*$` on a line, rather than any non-alnum), and exclude
`just do( not|n't)`. Then, in `last_user_msg()`, **do not honour a kill phrase found in the FIRST
genuine user record of a session that has exactly one** — a brief is a scope, not a stop order; the
operator who wants a fired session to stop has `cc-teardown` and the pane.
*Errs toward:* keeping the machinery armed when the operator wrote a genuinely terminal
"…and stop" inside a long brief. Cost of that error: one extra forced turn, which the model can
discharge with `session-continue.sh clear`. Cost of the current error: 100 measured writer sessions
running with every rail off. The asymmetry is ~100:1 in the corpus.
*Falsifier if wrong:* `kill-switch` / `ship-floor-kill-switch` IDL disposition rate rises above its
current 11-day baseline (19 + 6 events) while operator-typed stop orders start being ignored — visible
as a `clear` immediately after a block.
Files: `hooks/session-continue.sh`, `hooks/tests/session-continue*.bats`.

**R2 — Teach `session-writes.sh` to see Bash-mediated writes. (conviction 88%, effort M)**
Add a second selector for `tool_use` `name=="Bash"` whose `input.command` matches a write idiom, and
extract candidate paths from it; keep the existing three-state rc contract, and return **rc 2
(cannot tell)** rather than rc 1 when a Bash write is detected but no path can be resolved. That
single change flips 229 of 260 writer sessions today from "provably write-free" to "unknown", which
the floors already handle conservatively.
*Errs toward:* more mechanical 🔧 arms on sessions whose Bash writes were to `/tmp`. Bounded by
`CC_MECH_MAX` (2) and by the existing `git status` intersection, which already discards non-repo
paths — so a `/tmp` heredoc still cannot arm it.
*Falsifier if wrong:* `session-continue armed mechanical-dirty` (8 events in 11 days) rises without a
matching rise in commits, and `cli-clear` starts following it.
Files: `hooks/lib/session-writes.sh`, `hooks/tests/session-writes.bats`; backlog `ed54373d639b`.

**R3 — Re-key the assert-family caps on (sid, HEAD-sha) instead of (sid). (conviction 85%, effort S)**
`completion-assert` already has the pattern to copy: the ship floor latches per HEAD-sha and re-arms
on a new commit (`session-continue.sh:1030-1041`). Give `COMPLETION_MAX` and `ANTIDEF_MAX` the same
denominator, or reset them on a genuine (non-`isMeta`) user turn — which is exactly what the harness's
own `stopHookBlockingCount` does (§2). Today a 10-hour lead session gets 3 conviction checks total;
41 trips over 11 days, 29 of them suppressing a *later* close.
*Errs toward:* more blocks on a session that commits often. Bounded — the message-hash latch still
prevents re-firing on identical text, and a new HEAD means the facts genuinely changed.
*Falsifier if wrong:* `completion-assert fired` rate (114 in 11 days) more than doubles without the
`false-done` share rising, i.e. the extra fires are noise.
Files: `hooks/completion-assert.sh:1039-1080`, `hooks/anti-deference-nudge.sh:342-350`.

**R4 — A spent cap must be LOUD to the model and leave a row. (conviction 80%, effort S)**
Today `session-continue`'s cap path emits `{systemMessage:…}` (`:1126`) — and `systemMessage` is the
one Stop field that provably **cannot reach the model** (`docs/research/final-response-shaping-2026-08-08.md`).
So the named re-arm lever is addressed to a reader who never sees it. Since the caps release rather
than block, they cannot use `additionalContext` either without forcing a turn. The honest fix is
**stateful, not conversational**: on a cap trip, write the suppressed arm + rung into the IDL record
(§1.2) and file one `cc-backlog` row keyed on (sid, HEAD) so the silence has an owner.
*Errs toward:* a backlog row nobody drains — mitigate by making it auto-close when the session's next
close is clean.
Files: `hooks/session-continue.sh:1120-1130`, `hooks/completion-assert.sh:1075-1081`,
`hooks/anti-deference-nudge.sh:350`.

**R5 — Record `confirm_rc` on the mechanical assignee exemption. (conviction 95%, effort S)**
`session-continue.sh:846` logs `mechanical-assignee` with no detail while its sibling at `:974` logs
`{assignee, confirm_rc}`. The arm exempts on rc 2 (*cannot tell*) as well as rc 0, so 38 releases in
11 days are unattributable. One `jq -cn` argument.
*Errs toward:* nothing — pure instrumentation.
Files: `hooks/session-continue.sh:846`.

**R6 — Correct `CLAUDE.md`'s claim that `CLAUDE_CONTINUE_MAX` bounds runaway. (conviction 90%,
effort S)**
It bounds only the *mechanical* arm (as `CC_MECH_MAX × CLAUDE_CONTINUE_MAX`). For the agent-armed
path a compliant re-arm zeroes it, measured 0 trips in 11 days against a 311-block chain. Either say
so, or make `set` preserve `.count` when the sentinel is already armed for the same sid (a *refresh*
is not a *new chain*).
*Errs toward:* if you change the mechanism rather than the doc, a long legitimate grind starts
hitting the cap at 8 and must re-`set` explicitly — which is arguably the point. I would change the
doc first and measure, because for this operator's goal an unbounded driver is the *desired*
polarity and only the false claim is the defect.
Files: `~/.claude/CLAUDE.md` § Auto-continue actuation, `hooks/session-continue.sh:117`.

**R7 — Do not narrow the exemptions. (conviction 78%, effort none)**
The brief asks whether exemptions should narrow. Measured answer: no. `team-assignee` (80 per hook),
`teardown` (9), `headless` (0, and it emits an advisory rather than a silence), and the D6 origin
carve-out are all small, all recorded, and all defended in source with a stated reason. The
exemption that actually leaks is `ship-floor-not-mine` (90), and that is an *oracle* problem (R2),
not an exemption problem — narrowing the exemption would convict sessions over siblings' commits,
which is the `#105` lesson the codebase already paid for.

---

## §9 What this axis could not settle

- **How often the harness's own cap fires.** The override is a UI notification with no transcript
  record; 0 hits in 7.27 GB. Upper bound 44 chains ≥8 in 30 days; lower bound 0. Only
  `tengu_stop_hook_block_count` knows, and it is not written locally.
- **The lead's 901-closes-vs-469-evaluations gap.** Not the timeout (§7 i, refuted on today's size
  distribution), not caps (0 continuation trips, 1 completion cap today), not exemptions
  (~120 events today across all hooks). Something else — most likely sessions on config dirs whose
  `settings.json` does not register the chain, or `Stop` events the chain never received. Worth a
  separate axis.
- **How many of the 229 Bash-only writer sessions actually went idle with repo-dirty work.** My
  regex bounds the population at risk, not the realised harm; measuring it needs per-session
  `git status` at Stop time, which is not retained.
