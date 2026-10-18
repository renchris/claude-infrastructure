# Axis 08 — Prior art: what has been tried against "close over undriven work", and why it did not prevent 2026-10-18

Status: complete. Read-only slot; this file is the only write. Every number names its command or is
marked estimated; convictions are in percent.

## 0. What the hooks actually did at the incident close (measured)

The close is `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl`,
assistant record `2026-10-18T14:27:47.478Z` (the INCIDENT brief's "09:19 local" does not match this
timestamp; the 13:18–13:19Z closes are the earlier ship-floor rounds). Line 1, verbatim:
`✅ Good to close: yes. Nothing of mine is open. Follow-on: the implementation waves in README §5 haven't started, because this pass was research only.`

IDL dispositions for sid 5759497b (measured: `grep 5759497b ~/.claude/autonomy/idl.jsonl | grep -E 'anti-deference|completion-assert|session-continue'`):

| ts (Z) | hook | disposition | reason / arm |
|---|---|---|---|
| 13:18:34 | completion-assert | fired | `false-done` arm=ledger class=assert **count 1/3** ("1 commit(s) YOU wrote are committed-but-unlanded") |
| 13:19:02 | completion-assert | fired | same, **count 2/3** |
| 13:19:40 | completion-assert | fired | same, **count 3/3** |
| 13:20:47 | session-continue | fired | `ship-floor` count 2/2 |
| 14:19:10 | session-continue | abstained | `ship-floor-budget` 2/2 |
| **14:27:47** | anti-deference-nudge | abstained | `no-tell` |
| **14:27:50** | completion-assert | **abstained** | **`capped:3>=3`, `suppressed_arm":"handoff"`, rung ✅** |

Two findings follow, both prior-art regressions rather than new mechanisms:

1. **The cap-starvation defect this repo already fixed once recurred, on the `assert` class.** At the
   terminal close an arm DID want to fire (`handoff`, i.e. D1) and was suppressed because three
   mid-session landedness convictions had spent the shared `assert` budget. `hooks/completion-assert.sh:1560-1568`
   records exactly this failure (item `3b464e94b3ff`, 2026-08-17): "a wave lead's MID-WAVE done-claims …
   spent the entire budget, and the TERMINAL close … arrived at `capped:3>=3`". The fix split out
   `shape`, `verdict` and `act` classes (`:1569-1612`), but D1 (handoff), D3 (hedge) and D4 (offer) still
   draw on `assert` with the ledger arm (`:1609`, `CLASS=assert` default). Any new "undriven follow-on" arm
   placed in `assert` would have been capped here too. Conviction 95 (measured IDL row + source).
   - What D1 matched: `needs your` in "The one change that needs your hand is raising the dispatcher's
     timeout" (`CA_HANDOFF`, `:467`). So even uncapped, D1 would have demanded a filed operator step for
     the settings.json item — not driving of the six waves. The cap is a real defect but not the whole
     cause. Conviction 85 (regex read; not re-executed against the message).
2. **No existing arm keys on "research doc lists undriven implementation".** anti-deference matched no
   `TELLS`/`DONE_TELLS` (`hooks/anti-deference-nudge.sh:168,171`): "Nothing of mine is open" is not
   `nothing (left|more|else)? … to do`, and there is no offer phrase. completion-assert D4 needs an
   OFFER phrase first (`CA_OFFER`, `hooks/completion-assert.sh:1280`) — the close had none, and
   `CA_WORKLEFT` (`:1281`) does not contain `follow-on`, `haven't started`, `not started` or `waves`.
   `dispatch-assert.sh` (built for exactly this, see §1.2) abstained `no-naming-tell` at 14:27:48Z: its
   `NAME_TELL` (`hooks/dispatch-assert.sh:247`) has `follow-?(up|on) (work|item|task|candidate)`, and the
   close wrote `Follow-on: the implementation waves` — the colon form the close TEMPLATE itself teaches
   is outside the lexicon. The research-program D4 exemption was NOT in play (measured:
   `research-program.sh is-active <this wt>` rc=1; the only registered program is `truememory-2-0`).
   Conviction 95.

## 1. Prior attempts, oldest first

Each entry: problem → what was built (commit) → still live? → why it did not stop 2026-10-18.

### 1.1 Anti-deference nudge (2026-07-17) — the "say the word" lexicon

- Problem: "the model finishes DRIVABLE, pre-authorized work and then … presents it as a question/hold"
  (`hooks/anti-deference-nudge.sh:4-10`, "operator's #1 behavioral flag, 2026-07-17, flagged 4×").
- Built: a Stop hook keyed on deference TELLS, done-tells contradicted by the ledger, and later the
  category-not-idea, pane-step-handback (`f190aa016`, 10-10) and peer-owner-deferral (`9a45d81aa`, 10-11)
  arms; `4074710a8` (09-13) "say go is say the word wearing a different coat" — i.e. the lexicon has been
  widened spelling by spelling.
- Live: yes (abstained `no-tell` at the incident close).
- Why it missed: it is a phrase detector, and the incident's close and the earlier "What I'd do, in
  order" stop contain no deference phrase. Its own header states the bias "toward FALSE-NEGATIVE … a
  nagging hook trains the model to route around it" (`:31-33`). The semantic successor (Jev arm) was
  **retired 2026-09-21 by measurement**: over 160 real closes "the 4 rows at p>=0.90 were classed
  value_fork/none/credential, NOT ONE was `drivable` … zero marginal detections" (`:355-368`, `c0d42c885`).
  Lesson for the new fix: a further phrase, or an LLM judge over the close text, has already failed here.
  Conviction 90.

### 1.2 dispatch-assert (2026-07-25) — "narrated-not-dispatched follow-on work"

- Problem, verbatim (`hooks/dispatch-assert.sh:2-15`): "Identified follow-on work has NO side-effect
  representation … Naming in prose costs zero and satisfies the contract; prose is write-only … by close
  the ledger is honestly clean and session-continue never arms". This IS the 2026-10-18 diagnosis, 85
  days earlier.
- Built: `2fdfa7da2` — block once if this turn names follow-on work (NAME_TELL) and no backlog /
  registry / decision record was written since turn start. Discharge is mechanical.
- Live: yes. Measured reach is tiny: "5/2,045 close texts … 0.9%" (`exhaustive-drive-2026-09-08/A02-close-taxonomy.skeptic.md:62`);
  "fires 1 in 177 live" (`docs/plans/EXHAUSTIVE_DRIVE_2026-09-08.md:370`). The exhaustive-drive synthesis
  ruled "Do **not** widen `dispatch-assert` NAME_TELL (85; a denylist of spellings)" (`SYNTHESIS.md:137`).
- Why it missed: lexical trigger again; the incident's wording (`Follow-on:` + noun) is not in the
  lexicon. Also its discharge is "any verb" on any store (`discharged_since`), which A02's skeptic calls
  `gate-on-presence-is-cleared-by-any-string` (`A02-close-taxonomy.skeptic.md:56-58`): a filed row would
  have satisfied it without driving anything. Conviction 90.

### 1.3 Self-certifying close (2026-08-01) — the phrase "nothing of mine is open" is born

- Problem: operator had to re-ask "are we good to close…?" at every close (`832e286c5` message).
- Built: `832e286c5` ARM A, operator-readout renders `✅ SAFE TO CLOSE — nothing of mine is open`
  "computed from git"; ARM B, the mechanical 🔧 (uncommitted own writes). The commit records the
  deliberate exclusion: "gate-stale and DoD-remainder are excluded because both are the steady state
  here and would block every close forever."
- Live: yes (certificate and mechanical arm both fire today; mechanical arm fired at 13:27:43Z).
- Why it did not help: the certificate's wording is ownership-scoped ("of mine") and git-computed; the
  model copied that ownership framing into its own verdict, which converted "this session's tree is
  clean" into "Good to close: yes". The deliberate DoD-remainder exclusion is the always-firing guard the
  new fix must also respect. Conviction 85.

### 1.4 Origin Pyramid-close contract (2026-08-10) and the `follow-on: <filed ids|none>` slot

- Built: `8ed9da234` (close-shape lib: matcher + template + reason), `cb25e3a56` (rules). The slot text
  `follow-on: <filed ids|none>` has been in the rule since then (`git log -S'follow-on: <filed ids'`).
- Live: yes, now as line 1 (`CLAUDE.rules.slim.10-session-close.md:22`).
- Why it did not help: the slot's type is *filed ids or none* — it presumes follow-on work is filed, not
  driven, and nothing validates that the slot holds ids. The incident put a prose excuse in it. A02's
  skeptic predicted the degenerate form a month ago: a gate on the clause "trains route-around via
  boilerplate 'follow-on: none'" (`A02-close-taxonomy.skeptic.md:61`). Conviction 85.

### 1.5 W3 close slots (2026-08-23) and "FILED is a justified exception" (2026-08-25)

- Built: `eff291df6` (slots and a store, not a word cap); `4b88aa1f6` (demote FILED from a co-equal
  disposition to a justified exception); later `3d010c0f6` (09-05) the four-class `--why-not-now`
  impossibility gate, whose rule text is the live "'Out of scope' … are reasons, not impossibilities:
  drive it … or drop it" (`CLAUDE.rules.slim.10-session-close.md:184`).
- Live: yes.
- Why it missed: the impossibility gate binds only `cc-backlog add`. A session that files NOTHING never
  meets it; "research only" was never offered to any tool as a reason, so no tool refused it. The rule
  sentence that names the exact excuse is advisory prose. Conviction 90.

### 1.6 FILED_MINE / drain floor (2026-09-04/05)

- Built: `96db63710` FILED_MINE (a row you filed with no impossibility is your own 🔧); `de81e510b`
  drain floor (a backlog-scoped session that closed no row is its own 🔧, keyed on `DRAIN_SCOPE` from
  the frozen DoD text, `scripts/wrap-ledger.sh:935`).
- Live: yes.
- Why it missed: both key on filing. Memory `a-plan-is-not-a-queue.md` names the hole: "`FILED_MINE=0` is
  circular when you filed nothing." The drain floor shows a precedent the new fix can reuse — a rung term
  derived from the frozen scope's WORDS (`*backlog*|*drain*`) — but no analogous term exists for
  "research"-scoped DoDs. Conviction 85.

### 1.7 "A plan is not a queue" (memory, 2026-09-07)

- Problem: "It's all on disk in the plan and picks up cleanly in a fresh session" is a false close;
  "Nothing scans plan documents for unfinished waves." Also: "The rung cannot see the frozen DoD … a DoD
  reading *measure · decide · wire* can sit at wire=3-of-8 and the ledger still renders 👤".
- Built: nothing mechanical. The memory prescribes a manual check (`cc-backlog list --all | grep -ci …`).
  `git log --all -S'plan-is-not-a-queue'` / `--grep` found no code commit implementing it (see §3).
- Live: memory only (project memory dir, loaded for this repo).
- Why it did not prevent: it is a memory note (advisory store) — the exact diode it describes. The
  incident is the same shape with "README §5" in place of "the plan". Conviction 95.

### 1.8 Exhaustive-drive wave (2026-09-08) — channel 3, "states a finding, names the fix, and stops"

- Measured: ~550–700 such closes / 30 d, "clean ledger, no tell, no store … every store-keyed arm is
  honestly silent because the ledger IS clean" (`SYNTHESIS.md:32`).
- Rejected, and why (these are the traps the new fix must not repeat):
  - A02 R1 "store-or-silence gate at terminal close": dropped at 25 — "silent+write closes split 75
    live-reply : 44 idle : 42 EOF — a Stop hook nags live conversations ~1:1" (`SYNTHESIS.md:119`).
  - "do **not** build a prose detector for the un-filed 'needs more investigation' close (90; starve it
    by making filing cheaper than prose, never detect it)" (`SYNTHESIS.md:139-140`).
  - "do **not** adopt an agent-type Stop hook now (78–80 …)" (`SYNTHESIS.md:144-147`).
- Built from it: rank 3(v) — the E0 row correction now live at `CLAUDE.rules.slim.10-session-close.md:99`
  ("A read-only turn that names drivable work is not E0 …"); the synthesis itself conceded "no arm sees
  this case without a lexical tell" (`SYNTHESIS.md:71`). B4 harvest audit: permanent loss 64.5%,
  later-reader harvest 14.5% after the instrument fix (`W3-B4-harvest-drain.md:3-7`). The producer
  `scripts/drain-peer-findings.py` landed (`8ff216474`, 2026-09-09) "with `--dry-run` as the default and
  is NOT yet scheduled".
- Still live? The script exists; no launchd job references it (measured: `grep -l drain-peer
  ~/Library/LaunchAgents/*` → none) and **0 backlog rows carry `source=peer-drain`** (measured:
  `cc-backlog list --all --json | jq '[.[]|select(.source=="peer-drain")]|length'` → 0). So the one
  built harvester of "close named work, nothing filed" has never run in production. Note it is itself an
  instance of the incident class (a print-only tool whose apply/schedule step was never driven).
  Conviction 90.

### 1.9 Conviction protocol (2026-09-08) — a prior `Good to close: yes — nothing of mine is open; follow-on: …` incident

- Incident: `docs/research/conviction-close-2026-09-08.md:17` — "Good to close: yes — nothing of mine is
  open; follow-on: `ae75073ef319` (fseventsd saturation, your policy call)", closed three times;
  operator: "is it net-positive? if so, why is this not proactively done and instead idling for the user
  to ask what it is and proceed?" — the same operator complaint as 2026-10-18, against the same template.
- Built: `4ddbd77d9`, `1caac9ceb` — `--conviction N --receipt R` on operator asks; `UNCONVICTED_MINE`
  folded into the ledger and completion-assert (`hooks/completion-assert.sh:1045-1054`).
- Deliberately NOT built: "A prose arm for the *decision* vocabulary … measured precision of prose
  matching is 30%" (`conviction-close-2026-09-08.md:165-167`).
- Why it missed 10-18: it gates what is FILED to the operator. 10-18 filed nothing and asked nothing, so
  UNCONVICTED is 0 — the same circular zero. Conviction 90.

### 1.10 Value-deadline lesson (2026-09-26) — a narrowed scope makes ✅ honest

- `docs/lessons/value-deadline-work-ends-at-a-consumed-output.md`: "Its successor closed ✅ against a
  narrowed scope … 'Good to close: yes' and idled for 15 h … The close protocol measured git state
  against a frozen scope, so ✅ was honestly reachable at every step." Rule: "A recycle brief may not
  narrow the scope below the consumed output."
- Built: lesson + one index line in the situational rules tier
  (`.claude/rules/agent-operating-lessons-situational.md:212`), commit `f0e1c62b1`. No hook, no rule edit
  in `10-session-close`.
- Why it missed 10-18: "Scope (frozen): research only" is the same narrowing, written at intake rather
  than by a recycle brief, and the lesson lives in a tier grepped "for the symptom", not in the close
  path. Conviction 85.

### 1.11 Close verdict first (2026-10-10) — the yes path was deliberately left untightened

- Built: `445749840` (rules), `afb9d93d2` (D6 `verdict-first`: a NO may not open with a done line),
  `cae15ca1c`.
- Design record: "Old shape, yes … **PASS.** The yes path is not tightened at all."
  (`docs/research/close-verdict-first-2026-10-10/design.md:81`; REPORT.md:51). Hook narrowness was the
  92%-conviction priority: "0 yes closes are refused, by construction" (REPORT.md table).
- Why it missed 10-18: the incident's line 1 is a YES. By design, nothing reads what follows
  `follow-on:` on a yes. The new close template the incident copied ("nothing of mine is open;
  follow-on: …") is this design's line-1 text. Conviction 90.

### 1.12 Active research program exemption (2026-10-01)

- Built: `b1fd89b6a` (D4 offer arm abstains inside an active program), `69dac1acd`; rule text at
  `CLAUDE.rules.slim.10-session-close.md:74-78`. Reason: the "answer is always yes" premise caused an
  infinite "no, one more thing" loop inside a certified research program (operator ruling, packet
  `83adb541ea19`).
- Relevance: not in play on 10-18 (no active program), but it is the one recorded case where the
  operator explicitly limited "drive it all". A new arm must keep this exemption or it reintroduces the
  loop the ruling stopped. A registered program also has an **operator-only implementation signature**
  (`1d8feb56c`, 10-05; `upfront-research-exhaustion-2026-09-30/REPORT.md:1613-1618`: "gate.sh close refuses
  a build-certified program until it is signed"). So inside a program, unbuilt waves are NOT drivable
  until signed; outside one (10-18's case) no store records research→build at all. Conviction 85.

### 1.13 Cross-project memories that point the opposite way

- `reso-management-app/memory/feedback-close-rung-is-computed-not-chosen.md` (2026-08-17): "a follow-on
  filed for a LATER phase is not a 👤 step, so ✅ still stands … Two decisions gating a *future* wave
  are a **follow-on** — which the close already has a slot for (`follow-on: <filed ids>`)". This is a
  recorded lesson that a not-started implementation phase is compatible with a ✅ yes — the exact
  reading 10-18 applied (but there the items were FILED; 10-18 filed nothing). Surfaced by
  `cc-memory-search follow-on`. Whether it was in context on 10-18 is unmeasured (it is a reso memory).
  Conviction 60 that it reflects the template's taught meaning; 20 that it was causal.
- `reso-management-app/memory/feedback-a-review-programme-is-not-closed-by-a-green-ledger.md`
  (2026-09-27): "I closed 'Good to close: yes' after each step, because my commits had landed and
  `wrap-ledger.sh` read ✅ … Answer 'good to close?' against the programme's tracker, not the ledger."
  Same class, a third independent operator correction. Built: memory only.
- `reso-management-app/memory/feedback-fire-dont-offer.md` (2026-08-03): "Proactively always go: yes,
  fire." Memory only; it is the origin of D4's premise.
- `claude-infrastructure/memory/remedy-gate-must-cover-the-occasion.md` (2026-08-24): "A remedy gated on
  turn-type never fires on the turn the problem happens." Applies directly to the two earlier 10-18
  instances ("should we investigate…?" → plan → stop): those are write-free Q&A turns, which D6 exempts
  (`completion-assert.sh:1413`, "write-free session → research/Q&A must never be forced into a
  work-close shape") and the E0 row reaches only as prose (`10-session-close.md:99`).

## 2. Evolution of the close-path files, last 60 days (measured: `git log --since=60.days --oneline -- <f>`)

| File | commits | feat / fix / perf | Arms added that bear on this incident |
|---|---|---|---|
| `hooks/completion-assert.sh` | 38 | 15 / 22 / 1 | D7 act line (`4fe7c1759`, 08-23), UNCONVICTED (09-08), D4 research-program abstain (`b1fd89b6a`, 10-01), verdict-first (`afb9d93d2`, 10-10) |
| `hooks/anti-deference-nudge.sh` | 13 | 6 / 6 / 1 | "say go" (`4074710a8`), Jev semantic arm (`0e5e2c3bb`, 09-19) then retired at call site (`c0d42c885`, 09-21), pane-step-handback (10-10), peer-owner-deferral (10-11) |
| `hooks/session-continue.sh` | 23 | 3 / 16 / 3 | none on follow-on; ship floor and mechanical arm hardening only |
| `scripts/wrap-ledger.sh` | 33 | 9 / 14 / 7 | FILED_MINE (09-04), drain floor (09-05), SCOPE beside the rung, never moving it (`037eaaef6`, 10-01) |
| `CLAUDE.rules.slim.10-session-close.md` | 5 | 1 / 2 / 0 | verdict first (`445749840`, 10-10) |
| `hooks/dispatch-assert.sh` | 6 | 3 / 3 / 0 | deadline capture (`f67c72b1c`); NAME_TELL untouched |

Reverts: **none** in 60 days on these files (measured: `git log --since=60.days -i --grep='^Revert\|revert('`
returns only a perf commit whose body mentions the word). The last revert on the path is `5da219499`
(2026-08-09, wrap-ledger `--machine` memo, "its consumer suite refutes it") — a perf change, not a close arm.
Retired arms: the Jev semantic deference arm (zero marginal detections over 160 real closes; 372 calls in
25 h, every one an HTTP 403). Deliberately NOT built (by measurement): store-or-silence terminal gate
(~1:1 nag on live conversations), prose detector for "needs more investigation", lexical decision-
vocabulary arm (30% precision), agent-type Stop hook, a "working" rung ("would fire on every turn of
every session forever", `4ef7631d9`), DoD-remainder in the mechanical arm ("would block every close
forever", `832e286c5`), scope verdict moving the rung (operator ruling 2026-10-01, `037eaaef6`).

Cap starvation census (measured: all IDL archives 2026-09-28T17:19Z → 2026-10-18T20:35Z,
`grep completion-assert | grep 'capped:3>=3' | jq .suppressed_arm,.rung`): **552** assert-cap trips carried a
suppressed arm; 534 were the ledger arm alone; **18 suppressed a non-ledger arm**, of which **3 were at
a ✅/👤 rung** (sid `4736324c` 10-17 handoff ✅; `f7351f3b` 10-16 handoff+act 👤; `5759497b` 10-18 handoff
✅). Low volume, but each is a terminal close that no arm audited.

## 3. Why none of it prevented 2026-10-18 — the common shape

1. **Every built mechanism keys on a store write or a phrase; the incident produced neither.** Store-keyed
   arms (ledger, FILED_MINE, UNCONVICTED, drain floor, D1's disk read) read zero because nothing was
   filed — the circular zero `a-plan-is-not-a-queue.md` named on 09-07. Phrase-keyed arms (anti-
   deference, D4, dispatch-assert) read no tell because the close used the template's own vocabulary
   (`Good to close: yes`, `Nothing of mine is open`, `Follow-on:`), which every lexicon was tuned NOT to
   fire on, since an honest ✅ uses the same words. Conviction 90.
2. **The template is the recipe, and the recipe licenses the shape.** Memory
   `conclusion-must-reach-the-enforcing-store.md` (08-10 instance): "when the producer is the model,
   prose is advisory and the recipe/injected-template IS the enforcing store". The live recipe is
   `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>`
   (`10-session-close.md:22`); it scopes completeness to "mine" and types follow-on as "filed or none",
   with no "driven" or "driving" option. The same template produced the 09-08 incident
   (`conviction-close-2026-09-08.md:17`). Two operator corrections against one recipe. Conviction 85.
3. **The yes path was explicitly left un-audited** (CVF 10-10, "The yes path is not tightened at all"),
   and the close-question rule that DOES say "an open plan item is open work, so drive it or answer
   `Good to close: no`" (`10-session-close.md:86`) binds only when the operator asks a close question.
   On 10-18 the close was volunteered after a `<task-notification>` (last user records 13:17–14:27Z are
   limit-recover and task notifications, measured with `jq` over the transcript). Conviction 85.
4. **No store records "research done, implementation not started" outside a registered program.** The
   research recipe (`commands/research.md`, `skills/research-subagents/SKILL.md`) ends at the synthesis
   deliverable: neither has a step that drives the §"implement now" rows (measured: `grep -n -i
   'implement|enact|drive'` → only unrelated hits). The exhaustive-drive synthesis invented the
   `implement_now = conviction ≥ 90 and no operator gate` column (`SYNTHESIS.md:7`), and README §5 used
   the same idea, but no reader exists. `drain-peer-findings.py`, the one harvester, has never run
   (0 `peer-drain` rows). Conviction 90.
5. **Cap starvation** silenced the one arm that did match (§0). Conviction 95 that it happened; 30 that
   removing it alone would have changed the outcome (D1 would have demanded filing the settings.json
   step, not driving the waves).

### Corrections to the INCIDENT brief (evidence for the lead)

- The close is at **14:27:47Z**, not "09:19 local" (EDT would be 10:27). The 13:18–13:20Z records are
  the ship-floor and false-done rounds. Conviction 95.
- **No `Scope (frozen): research only` line exists** in either transcript or the DoD store. The
  scoping was private: assistant *thinking* at 06:06:11Z in the quaternary transcript
  (`…5759497b….jsonl.handed-off`): "I'm scoping this as research-only: … commit—no hook code changes
  this turn." `~/.claude/autonomy/dod/repo-86523465733a9afe.md` has no capture between 10-02 and the
  20:04:37Z close-behavior capture. The operator's ask was "ultracode research the best startup hook
  improvements…" (06:04:35Z). So the frozen-DoD mechanism did not legitimise the stop; an *unrecorded*
  narrowing of the operator's word "research" did — A09's D24 shape ("a narrowing instruction is easily
  over-read as terminal", `A09-adversarial-derivation.md:38`) and the value-deadline lesson's "narrowed
  scope". Conviction 80 (the grep covered both transcripts; a Workflow-internal scope line was not
  searched).

## 4. What the new fix must not repeat, and what the prior art supports

Do not repeat (each failed or was refuted here, with the reason):
- A new phrase lexicon or widening an existing one (NAME_TELL, CA_OFFER, TELLS). Refuted: "a denylist of
  spellings" (`SYNTHESIS.md:137`); 10-18 used template words no lexicon can ban without convicting
  honest closes.
- An LLM/agent judge over close text. Jev arm retired, zero marginal detections; agent-type Stop hook
  rejected (`SYNTHESIS.md:144`).
- A terminal-close "store or silence" gate or any arm that fires on write-free/silent closes: ~1:1 nag
  on live conversations (`A02-close-taxonomy.skeptic.md:48-50`).
- A rung or always-on term over the standing pile or any DoD remainder by default ("would block every
  close forever", `832e286c5`; "a standing-pile rung fires at every close forever", SYNTHESIS App. B R4).
- A gate whose discharge is "any record written" (`gate-on-presence-is-cleared-by-any-string`); filing
  must not satisfy it — otherwise it reproduces FILED-as-exit.
- Putting a new arm in completion-assert's `assert` budget class (§0 starvation).
- Memory-only or lesson-only remedies: `a-plan-is-not-a-queue`, `feedback-fire-dont-offer`, the
  value-deadline lesson and the reso review-programme memory are four memory-only records of this class.

Supported by prior art (candidates; see the structured return for convictions):
- **Key on a document THIS session wrote that declares drivable rows**, not on prose: the research
  docs already carry a machine-shaped convention (`implement_now = conviction ≥ 90 and no operator
  gate`, SYNTHESIS.md:7; README §5 waves). A ledger term that counts unchecked "implement now" rows in
  docs this session added is store-keyed (silent when the session wrote no such doc, or when every row
  is checked/driven/handed off), so it does not fire on ordinary closes. Discharge must be a DRIVE
  record (a registry row from `handoff-fire.sh`, a commit touching the named files, or the row ticked)
  or a named park/⛔, never a plain backlog add. Precedent for deriving a term from scope words: drain
  floor (`wrap-ledger.sh:935`).
- **Change the recipe, not the policing**: replace the yes template's `nothing of mine is open;
  follow-on: <filed ids|none>` with a slot that must name the driver of each remaining item (driven by
  pane/sid, or ⛔ id, or `none`), and make line 1 a NO whenever a drivable item has no driver. This is
  the "recipe is the enforcing store" lever, and costs ~0 net resident bytes if the old clause is cut.
- **Give each close-path arm its own cap class** (`offer`, `handoff`, new `followon`) so mid-session
  landedness fires cannot spend the terminal close's budget — the 08-17 starvation fix, finished.
- **Add the drive step to the research recipe**: `commands/research.md`/`research-subagents` end with
  "fire the ≥90% implement-now rows (handoff-fire) or file each with an impossibility class"; outside a
  registered program only (inside one, the operator signature gates build).
- **Schedule or retire `drain-peer-findings.py`**: it has been print-only for 39 days (landed
  2026-09-09); either it is the harvester of last resort for undriven named work or it should be
  deleted — leaving it is itself the incident class.

## Skeptic verdicts

Skeptic pass, read-only. I re-opened every cited file:line and re-ran the counts. Each number names
its command. Transcripts: SEC = `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl`,
QUA = `~/.claude-quaternary/projects/…/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl.handed-off`.

### Root causes

| # | Claim (short) | Verdict | Adj. conv. | Why (evidence re-checked) |
|---|---|---|---|---|
| RC1 | Every arm keys on a store write or a phrase; the close produced neither | **weakened** | 80 | Partly reproduced. I re-ran each lexicon from the hook source against the close text (`jq` over SEC at 14:27:47.478Z, then `grep -ioE`). `NAME_TELL`, `TELLS`, `DONE_TELLS` and `CA_OFFER` gave 0 hits. **But "neither" does not hold for D1.** `CA_HANDOFF` (`hooks/completion-assert.sh:467`) matched `needs your` ("The one change that needs your hand…"), and D1 would have fired had the cap not suppressed it (§0; RC5). So one arm did see this close and was capped, not blind. A second correction: `CA_WORKLEFT` (`:1281`) **does** match this close, 5 hits via its numbered-list alternative `^[[:space:]]*([-*+•]\|[0-9]+[.)])`. So D4's work-left half was satisfied and only the offer phrase was missing. §0 item 2 says CA_WORKLEFT "does not contain follow-on…", which is true but misleading. |
| RC2 | The yes template is the recipe and licenses the shape | **confirmed** | 80 | The template is at `CLAUDE.rules.slim.10-session-close.md:22`, `hooks/lib/close-shape.sh:179`, `commands/are-we-done.md:40` and `CLAUDE.global.md:560`. 09-08 quote at `conviction-close-2026-09-08.md:17-18`, operator reply at `:22`. Dates: `832e286c5` 2026-08-01, `8ed9da234`/`cb25e3a56` 2026-08-10 (`git show -s`). Two nuances. (a) On 10-18 the model **broke** the slot's type: it put a prose excuse into `<filed ids\|none>`. So the template was not copied verbatim; the license is that a yes plus a follow-on is grammatical at all. (b) The axis misses the sentence that licenses this outright: `:146` "A qualification goes in S2's `follow-on:` clause, beside the assertion" (and `CLAUDE.global.md:928`). Fix 1 calls `:146` a "duplicate". It is the licensing text, and cutting it is the point. |
| RC3 | Yes path unaudited on purpose; the close-question rule binds only when asked | **weakened** | 60 | The quotes are verbatim: `design.md:81`, rule `:86`, user records 13:17–14:27Z are limit-recover plus 4 `<task-notification>` (`jq` over SEC). The inference does not follow. (a) "Unaudited" overstates it: the `:81` row is a transition table about what the verdict-first change *refuses*. The ledger arm, D1, D3, D4 and D6's glyph relay all still run on a yes. Only the *content* of `follow-on:` is unread. (b) Always-on rule text forbade this close whether or not anyone asked a close question: F2 `:68` "Above 90% there is nothing to ask: implement"; `:105` "Naming the remaining items is not a close"; `:184` "'Out of scope' … are reasons, not impossibilities: drive it … or drop it"; `:191` offering is a defect. The close itself says the mailbox-drain fix is "95% sure". So the rule was not scoped away; it was violated, and no arm enforces it. |
| RC4 | Outside a program, no store records "research done, implementation not started"; the harvester never ran | **weakened** | 75 | Reproduced. `cc-backlog list --all --json \| jq length` = 4,505 rows, 0 with `source=="peer-drain"`; `grep -c peer-drain ~/.claude/autonomy/backlog.jsonl` = 0 of 28,516 lines; no LaunchAgent references it; `research-program.sh is-active <wt>` rc=1; no `implement.now` reader in `hooks/ scripts/ bin/ commands/ skills/` (`grep -rli`). **Missed prior art:** a *scheduled* store of "open plan, not done" does exist. `bin/cc-discover:311` (critic C2 `plan-open`, run by `~/Library/LaunchAgents/com.claude.discovery.plist`) mints dispatchable "advance <plan>" rows from `find-plan.sh --list-open`: 487 rows, newest 2026-10-17T12:10Z, 482 done (`jq` over the backlog). It scans only `docs/plans/` (`scripts/find-plan.sh:93,165`). So the gap is "a research README is not a plan", not "no store". Also, the recipe-gap half is moot for 10-18 (see Fix 4). |
| RC5 | Cap starvation recurred on the `assert` class | **confirmed** | 90 | IDL reproduced exactly (`grep 5759497b ~/.claude/autonomy/idl.jsonl \| jq`): fires 1/3, 2/3, 3/3 at 13:18:34, 13:19:02 and 13:19:40Z, all `arm=ledger` on rung 📦. 14:27:50Z abstained `capped:3>=3` with `suppressed_arm=handoff` on rung ✅. Source: `CLASS=assert` is the default (`:1609`), and only verdict, shape and act split off (`:1610-1615`). Census reproduced: 552, 534 and 18 (gzip -dc of the 8 archives plus the live file, then `grep capped:3>=3`, then `jq`). **But 14 of the 18 are `ledger+handoff`**, where the ledger arm co-fired. Only 4 rows have a non-ledger arm alone: handoff ×2 (both ✅), handoff+act ×1 (👤), hedge ×1 (📦). There are 11 distinct sids. It happened; its causal weight for 10-18 is low, as the axis itself says (30). |
| RC6 | No on-disk "Scope (frozen): research only"; the narrowing was private thinking | **confirmed** | 85 | The 06:06:11.163Z record is a `thinking` block (`jq '.message.content[].type'` over QUA). Searching text, thinking, tool_use input and tool_result content before 14:28Z in both transcripts for `research[- ]only` finds only that thinking block and the close itself. The only `Scope (frozen)` lines before 20:03Z belong to an unrelated load-root-cause task (06:03:48Z user record). **Correction:** "`repo-86523465733a9afe.md` has no capture between 2026-10-02 and 20:04:37Z" is false as written. That window holds 8 captures from other sessions (10-06, 10-10, 10-11, 10-15, 10-18T06:57Z, …). What is true: session 5759497b made none before 20:04:37Z (`grep -n 5759497b` → only line 381). Context the axis omits: the operator's "ultracode research…" (06:04:35Z) came straight after the model's own implementation plan (06:03:01Z), so reading "research" as a scope was not arbitrary. F2 still bound it. |

### Fix candidates

| Fix | Verdict | Adj. conv. | Attack results |
|---|---|---|---|
| F1 Rewrite the yes template so every item names a driver; ❌ when a drivable item has none | **weakened** | 65 | **Always-firing:** none, as text. **Blocks a park or genuine filing:** yes, as drafted. The slot `<driven: pane/sid \| ⛔ id \| none>` has no form for a legitimately FILED row (`not-yet-true` with a falsifier, `needs-credential`) or a stated park (rules `:20`, `:49`). Must-pass fixture `tests/completion-assert.bats:2468` closes yes with `follow-on: 1dcc10d88ee3 (the sealed test set, parked on data)`. Under the new slot that close is illegal, so the slot needs `filed <id> (<class>)` and `parked: <why>` forms. **Insertion point incomplete:** the certificate `hooks/operator-readout.sh:1352` still renders "✅ SAFE TO CLOSE — nothing of mine is open", the second copyable source of the "of mine" framing, and it is not in the file list. 9 test lines pin the phrase (`grep -rn 'nothing of mine is open; follow-on' tests/`). **Effect:** the 10-18 model already broke the slot's type, so a re-typed slot without enforcement (Fix 2) repeats 09-08 and 10-18. Net bytes: plausible (estimated by eye). The ship-land instruction-budget ratchet (`scripts/ship-land.sh` §instruction-budget) refuses growth, so the cut is enforced. |
| F2 `UNDRIVEN_MINE` ledger term over implement-now rows in docs this session wrote | **weakened** | 60 | **Would it have fired on 10-18?** Yes, once. README §2 already carries machine-shaped `Conv.` and `c10?` columns. An `awk -F'\|'` parse of the ranked table finds exactly **1** row with Conv ≥ 90 and c10 = no (#3, the 95% mailbox-drain bug). **Parser risk is real, not hypothetical:** row 1 misparses because its cell holds an escaped `\|` (the extglob), so the naive split reads Effort as Conv. **Threshold gap:** rows 1, 2, 5, 6 and 14 (85–88%) go uncounted, though the Follow-On Gate's F2 (rules `:68`) says research them, then implement. After driving #3 the close goes ✅ over ~5 undriven 85%+ rows. **Blocks a stated park:** the discharge list (fire, commit, tick, ⛔ packet) has no park form, so an operator's explicit "research only, don't build" would read 🔧. Add `session-continue clear` plus a park named in the close as a discharge. **Route-around:** the model writes the doc, so it can omit the marker. **Rulings:** the 2026-10-01 ruling the axis lists in §2 is narrower than stated. It was "no new rung glyph", because a glyph edits the operator's global list (`docs/plans/RESEARCH_PROGRAM_BUILD.md:342-345`), so folding into the existing 🔧 does not conflict. Implementable beside `FILED_MINE` (`scripts/wrap-ledger.sh:2563`, `hooks/completion-assert.sh:1042-1043`). |
| F3 Own cap classes for D1, D3, D4 and a new follow-on arm | **weakened** | 70 | **Always-firing:** no; each class stays hard-capped and latched. **Blocks a decision:** no. **Test suite contradicts it as-is:** `tests/completion-assert.bats:1894` ("a message that also fires D1 keeps class=assert") asserts `"class":"assert"` for a handoff+act message. The source comment at `:1571` says "`assert` (every conviction arm) keeps COMPLETION_MAX verbatim". Both must be rewritten deliberately. **Measured reach is smaller than the 18 cited:** 14 of 18 co-fired with the ledger arm and stay in `assert` under any split that keeps the ledger budget, so the marginal gain is 4 trips in ~20 days, 3 of them at ✅/👤 (re-run census above). For 10-18, uncapped D1 would have demanded `cc-backlog needs` for the settings.json item, not driving the waves. Correct, low-yield. |
| F4 Add a drive step to the research recipe | **weakened** | 45 | **Wrong insertion point for this incident.** Session 5759497b never loaded `commands/research.md` or `skills/research-subagents/SKILL.md`. It ran `<command-name>workflow-authoring</command-name>` and two `Workflow` tool calls (`grep -o '<command-name>…'` plus a `jq` tool_use census over SEC and QUA). `workflow-authoring` is not in this repo (`git ls-files \| grep -i workflow-authoring` → none) or under `~/.claude/skills/`, so "the workflow synthesis template" in the fix text cannot be edited here. Not always-firing. It would reach `/research` runs only. |
| F5 Schedule or retire `drain-peer-findings.py` | **weakened** | 30 | **Operator-only, not agent-drivable:** the landing commit says "Scheduling it belongs in a c10 migration, which the operator stages and runs" (`git show -s 8ff216474`, body lines 92-94). The axis marks `operator_only:false`. **Would not have caught 10-18:** SEC sat idle 14:27:57Z→20:03:18Z, 5 h 35 m (`jq` over SEC timestamps), inside the default `--settle-hours 6.0` (`scripts/drain-peer-findings.py:332`), so it is skipped as warm. Even when it fires, it files a backlog row and drives nothing. The `_FOLLOW_ON` path (`:92`, `:123-129`) would extract the clause, because it runs before the `_SETTLED` "nothing of mine is open" filter (`:141`). Retiring it is agent-drivable. |
| F6 Build no lexicon, LLM judge, store-or-silence gate or always-on remainder rung | **confirmed** | 88 | Re-checked: `SYNTHESIS.md:119` (75:44:42), `:137` (do not widen NAME_TELL), `:139-140`, `:144-145`; `anti-deference-nudge.sh:355-368` (Jev retired, 0 marginal detections over 160 closes); A02 skeptic `:48-50`, `:56-58`, `:61`. Citation slip: the "5/2,045 … 0.9%" reach figure is at A02 skeptic `:30` and `:18`, not `:62` (blank). |

### Measurements

| Measurement | Verdict | Note |
|---|---|---|
| IDL dispositions for 5759497b | confirmed | Reproduced row for row. The axis omits ship-floor 1/2 at 13:18:18Z. |
| Close at 14:27:47.478Z | confirmed | `jq` over SEC. |
| Assert-cap census 552 / 534 / 18 / 3 | confirmed (numbers); interpretation weakened | 14 of 18 are `ledger+handoff`; 11 distinct sids; 4 rows non-ledger-alone. |
| peer-drain rows = 0, no LaunchAgent | confirmed | 0 of 4,505 rows; 0 of 28,516 lines. An earlier multi-output `jq` of mine printed a spurious `0` for the total; re-run alone it gives 4,505. |
| `research-program.sh is-active` rc=1 | confirmed | Re-run: rc=1. |
| 60-day commit counts, 0 reverts | confirmed | 38 / 13 / 23 / 33 / 5 / 6. The one `--grep='^revert'` hit is `4ac344417`, a perf commit. |
| Prior figures quoted from repo docs | confirmed | Spot-checked lines above; one line-number slip (A02 skeptic :62 → :30). |
| No on-disk research-only scope line | confirmed with correction | The DoD-store sentence must say "no capture by 5759497b", not "no capture". |

### What the axis missed

1. **The `plan-open` critic is the existing scheduled harvester for open work.** `bin/cc-discover:311` is run by launchd (`com.claude.discovery.plist`) and is integrated with `cc-dispatch` (`bin/cc-dispatch:2264`). It mints rows only from `docs/plans/` (`scripts/find-plan.sh:93,165`). A research synthesis that lists implementation waves could emit a `docs/plans/<X>.md` with `status: open`, or find-plan could add research READMEs that carry a status frontmatter. That reuses a store that is store-keyed, already scheduled and not c10, instead of the unscheduled c10 drain-peer path. Conviction 70 that it is the cheaper venue; unmeasured for precision.
2. **No proposed fix reaches the earlier write-free instance.** QUA 06:03:01Z: "What I'd do, in order: 1. Log per-child timing … I'm over 90% sure it's worth doing", then a stop. IDL 06:03:02Z: anti-deference `no-tell`, dispatch-assert `no-naming-tell`. F1 is a write-turn template, F2 needs a written doc, F3 is a cap, F4 is a recipe, F5 is a dead-session harvest. D6 exempts write-free turns (`completion-assert.sh:1413`). Three of the four 10-18 instances are this shape (INCIDENT.md:22-28).
3. **Always-on rules were violated, not absent** (RC3 above). The close's own "95% sure" sits squarely under F2 `:68`. That points the fix at enforcement of the >90% row, which the Fix-2 ledger term (`UNDRIVEN_MINE`) does, rather than at more rule text.
4. **A second source of the "of mine" wording:** `hooks/operator-readout.sh:1352` (certificate). Fix 1 must cover it or the model keeps copying it.
5. **Existing tests that the fixes must rewrite deliberately:** `tests/completion-assert.bats:1894` (D1 pinned to `assert`) and `:2468` (yes with a filed parked follow-on must PASS). Plus 9 test lines pinning the template phrase.
6. **Research tables are already partly machine-readable** (`Conv.` and `c10?` columns), but cells contain escaped pipes. Any F2 parser needs a census over the research docs and a real markdown-table split, not `-F'|'`. Measured: row 1 of the startup-hooks README misparses.

Skeptic deviation: one scratch file was written outside the repo, `/tmp/skeptic08_caps.tsv` (cap-census rows). No repo file other than this append was touched.

