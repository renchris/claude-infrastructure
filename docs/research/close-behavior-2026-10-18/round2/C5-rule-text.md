# C5: rule text — remove the `follow-on:` licence and the "research only" exit

Round 2, 2026-10-18. Candidate C5 (rule text) from `axes/01-rule-text.md` and its `## Skeptic verdicts`.
Read-only in the repo; every prototype edit and test run is on copies under `/tmp/r2-C5/`. Every number is
labelled measured (with the command) or estimated (with the method).

Status: in progress (written incrementally).

## 0. Setup facts and brief corrections

- Repo copy for test runs (measured): `rsync -a --exclude=.git --exclude=docs --exclude=node_modules ./ /tmp/r2-C5/repo/`
  (184M). Pristine originals of the four edited files in `/tmp/r2-C5/orig/`.
- **Brief correction 1.** The brief names `scripts/why-tier.sh:90-91`. That path does not exist
  (`ls scripts/why-tier.sh` -> "No such file or directory"). The licence lives in `hooks/lib/why-tier.sh:90-91`
  (the `--why hedge` body), and the template again at `hooks/lib/why-tier.sh:172-173` (`--why shape`).
- **Brief correction 2.** The slim close-rules file and global were last changed by `cae15ca1c`/`0ca2315a3`/`2b9d938de`
  (`git log --oneline -3 -- <files>`); line numbers below are the current tree (slim:22 template, slim:146 licence,
  slim:156 S6 catch-all, global:560-561 template, global:927-929 licence, global:982 S6 catch-all).
- The slim global header records `derived-from CLAUDE.global.md sha256:cecd5a0c2fa35792`; the current full text
  hashes to `2f5ed0e7def902cc` (measured, `shasum -a 256 CLAUDE.global.md | cut -c1-16`). The variant is already
  STALE per `bin/cc-instructions-variant` status (an informational line, not a test or gate), so a global edit
  does not create a new staleness; it is a column-0 HTML comment and costs 0 loader chars.

## 1. Baseline (measured)

| File | loader units | bytes | how |
|---|---|---|---|
| `CLAUDE.rules.slim.10-session-close.md` (= live `~/.claude/rules/10-session-close.md`, `diff -q` silent) | 30,317 | 30,984 | `python3 -I /tmp/r2-C5/bin/units.py` (calls the repo's own `instruction_budget.parse`; identical to `len(strip_comment_blocks(s).encode('utf-16-le'))//2`) |
| `CLAUDE.global.slim.md` | 28,343 | 28,840 | same |
| live user tier (`CLAUDE.md` + `00-mission-board.md` + `10-session-close.md`) | **60,998** vs budget 60,000 | | `python3 -I /tmp/r2-C5/bin/tier.py` (`Loader(DiskFS()).user("~/.claude").total()`) |

The tier is already 998 over budget, so `judge()` admits only a change whose tier total does not grow
(`nt > budget and nt > ct` refuses). Control (measured, `/tmp/r2-C5/bin/judge_ctl.py`): appending one
character to the live rules text returns a `kind: tier` refusal for all five config dirs (60,998 -> 60,999).
So "budget-negative" here is not a style preference; any growth is refused by the Write/Edit gate on the
live file.

## 2. Where the two paths actually run through the text (re-read, current tree)

1. **The licence.** slim:146 ends `A qualification goes in S2's \`follow-on:\` clause, beside the assertion.`
   The template it qualifies, slim:22, admits only `follow-on: <filed ids|none>`. Mirrors:
   global:927-929 (`anything that would withdraw the assertion goes in S2's \`follow-on:\` clause, *beside*
   it, never below it`), `hooks/lib/why-tier.sh:90-91` (`--why hedge`, the body D3 hands the agent at the
   moment it fires). slim:156 / global:982 add a second catch-all (`let S2's \`follow-on:\` clause cover it`).
2. **The yes payload is a git predicate.** slim:22 `yes — nothing of mine is open` is the same string the
   git-computed certificate prints (slim:8, `hooks/operator-readout.sh:1352`). In the incident the
   certificate never rendered (operator-readout timed out, axis 01 check 4), so the agent wrote "Nothing of
   mine is open" from the template text alone (axis 01 RC2, confirmed 80). It was true of git and false of
   the task. Copies of the template: `hooks/lib/close-shape.sh:179` (the ONE template source D6 and `/wrap`
   print), `hooks/lib/why-tier.sh:172-173` (`--why shape`), `commands/are-we-done.md:40`, global:560.
3. **"Research only".** No `Scope (frozen):` line existed (axis 01 M6), so slim:26 was not the fence. The
   agent's own framing ("this pass was research only") was offered as the reason a Gate-passing item (one
   bug fix at 95%, F2: "Above 90% there is nothing to ask: implement") was neither driven nor filed, inside
   the licensed `follow-on:` slot. Nothing in the close section ties the Follow-On Gate to the verdict.
   `commands/are-we-done.md:55-59` lists the `yes` preconditions and every one is a git or ledger fact.

Reachability: an agent writing line 1 copies slim:22 and is licensed by slim:146. Both are inside the close
section the incident session had resident (axis 01 check 3: only the slim text was loaded). The global and
command copies are not resident but are what `/are-we-done`, `/wrap` and the D3/D6 reasons print, so they
must move with the slim text or they re-teach the licence.

## 3. Design: the edit set

Rules for choosing edits: only edits the axis 01 skeptic did not refute (E1 weakened 70, E2/E3 weakened 72,
a narrowed E5 with the carve-out the skeptic demanded), with every fix the skeptic named folded in; no
cut of a pinned span (X1-X5 refuted: `tests/research-program-exemption-rules.bats` pins them); no new
matcher; no edit to the six files another session owns; no settings.json. Prototype: `/tmp/r2-C5/bin/edits.py`
(asserts every old string occurs exactly once, prints the UTF-16 delta, applies to a copy). Core applied to
`/tmp/r2-C5/core/`, core + optional to `/tmp/r2-C5/repo/`.

### 3.1 Core (closes both paths, removes every copy of the licence)

| id | file:line | old | new | delta (UTF-16, measured) |
|---|---|---|---|---|
| S-a | slim:22 | `` `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids\|none>` `` | `` `✅ Good to close: yes — nothing drivable is open; follow-on: <filed ids\|none>` `` | +1 |
| S-b | slim:146 | `; if it is immaterial, it stays out. A qualification goes in S2's `` `follow-on:` `` clause, beside the assertion.` | `; if it is immaterial, it stays out; unfiled work the Follow-On Gate passes that nobody drives makes S2 a no, "research only" or not.` | +25 |
| S-c | slim:156 | `; when nothing is, omit S6 and let S2's `` `follow-on:` `` clause cover it.` | `; when nothing is, omit S6.` | -42 |
| G-a | global:560 | `` `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids\|none>` or `` | `` `✅ Good to close: yes — nothing drivable is open; follow-on: <filed ids\|none>` or `` | (unbudgeted) |
| G-b | global:927-929 | `at all. Never both — and⏎anything that would withdraw the assertion goes in S2's `` `follow-on:` `` clause, *beside* it, never below⏎it. A plain` | `at all. Never both. Unfiled work⏎the Follow-On Gate passes that nobody drives makes S2 a no, "research only" or not (on 2026-10-18 a⏎yes carried six undriven implementation waves in its `` `follow-on:` ``). A plain` | (unbudgeted) |
| G-c | global:981-982 | `Omit S6⏎when nothing is theirs; S2's `` `follow-on:` `` clause discharges it.` | `Omit S6⏎when nothing is theirs.` | (unbudgeted) |
| W-a | why-tier.sh:90-91 (`--why hedge`) | `appear in the rung line at all. Anything that would withdraw the assertion goes in the `` `follow-on:` ``⏎clause of the Good-to-close line — beside the verdict, never below it. A plain⏎` | `appear in the rung line at all. Unfiled work the Follow-On Gate passes that nobody drives makes the⏎verdict a NO, "research only" or not; `` `follow-on:` `` holds only filed ids, each with its gloss. A plain⏎` | (on demand) |
| W-b | why-tier.sh:172-173 (`--why shape`) | `` `✅ Good to close: yes — nothing of mine is⏎     open; follow-on: `` | `` `✅ Good to close: yes — nothing drivable is⏎     open; follow-on: `` | (on demand) |
| T-a | close-shape.sh:179 (companion: the ONE template D6 and `/wrap` print) | `Good to close: <yes — nothing of mine is open; follow-on:` | `Good to close: <yes — nothing drivable is open; follow-on:` | (code) |
| A-a | are-we-done.md:40 (companion) | `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids \| none>` | `✅ Good to close: yes — nothing drivable is open; follow-on: <filed ids \| none>` | (on demand) |
| A-b | are-we-done.md:58 (companion: the `yes requires ALL of` list) | `frozen-DoD remainder 0 · custody carries no row with YOUR marker. Any one unknown ⇒` | `frozen-DoD remainder 0 · custody carries no row with YOUR marker · no unfiled work the Follow-On⏎Gate passes that nobody drives, "research only" or not. Any one unknown ⇒` | (on demand) |

(`⏎` = a newline inside the exact string; the machine-exact strings are in `/tmp/r2-C5/bin/edits.py`,
`python3 -I /tmp/r2-C5/bin/edits.py <root> full --dump` prints them as Python reprs.)

Why each, in one line:
- **S-a** removes the git-scoped predicate from the yes payload (axis 01 RC2, confirmed 80). The certificate
  (slim:8, `operator-readout.sh:1352`) keeps "nothing of mine is open", which is true of git; the verdict now
  asserts the thing the close question asks. Writing it over six drivable waves is a false statement, not a
  true one about git. Wording chosen by measurement, see §4.4: "nothing drivable remains" was rejected.
- **S-b** deletes the licence and puts its inverse in the same sentence that already routes every other
  kind of qualification (parked/theirs -> the rung, immaterial -> out). It ties the Follow-On Gate to the
  verdict (axis 01 §1(c): "Nothing makes running the Gate a precondition of ✅ or of a yes") and names the
  incident's exact excuse. It needs no exception list: parks and operator-owned items are routed by the
  preceding clause, filed items and ⛔ decisions are excluded by "unfiled", and a fired peer by "nobody drives".
- **S-c** deletes the second catch-all. `omit S6` is complete on its own.
- **W-a** is the skeptic's E2/E3 completion item: D3 hands the agent this body at the moment it fires, so
  leaving it would re-teach the licence exactly when a hook is correcting a close.
- **G-\***, **W-b**, **T-a**, **A-a** keep every copy of the template and the licence in agreement (one concept,
  one wording). **A-b** closes the same path in the operator's own close-question command, whose `yes`
  list is otherwise all git and ledger facts.

### 3.2 Optional

| id | change | where | delta (slim) |
|---|---|---|---|
| D (recommended) | `who owns it` -> `who drives it` in the no-form | slim:22; global:561, 929, 944; why-tier.sh:92, 173; close-shape.sh:179; are-we-done.md:49, 59 (`which check, and who drives it`); wrap.md:176 | +2 |
| E (not needed) | `Read-only / advisory / research (no tracked writes)` -> `Read-only / advisory (no tracked writes)` | slim:34, global:601 | -11 |

### 3.3 Budget (measured)

| set | slim rules units | global slim units | projected user tier | `judge()` on the live rules path |
|---|---|---|---|---|
| baseline | 30,317 | 28,343 | 60,998 | n/a |
| core | 30,301 (**-16**) | 28,343 (0) | 60,982 | `[]` (admitted) |
| core + D + E | 30,292 (**-25**) | 28,343 (0) | 60,973 | `[]` (admitted) |
| core + D (recommended) | 30,303 (**-14**, measured `/tmp/r2-C5/bin/coreD.py`) | 28,343 (0) | 60,984 | admitted (same rule: no growth) |

Commands: `python3 -I /tmp/r2-C5/bin/units.py <file>`; `python3 -I /tmp/r2-C5/bin/judge.py` (calls
`instruction_budget.judge(live_path, cur, new, cfg)` with a DiskFS overlay, no write). `CLAUDE.global.slim.md`
is not touched, so the resident pair shrinks by the slim-rules delta alone. The tier stays over its 60,000
budget (it was 998 over before this change); the change does not fix that and does not make it worse.

## 4. Measured evidence that the set is safe

### 4.1 The contradictions are gone

`grep -n -F -e 'beside the assertion' -e 'withdraw the assertion goes' -e "let S2's" -e 'clause discharges it'
-e 'nothing of mine is open; follow-on'` over slim, global, global slim, why-tier.sh, close-shape.sh,
are-we-done.md, wrap.md: pristine worktree 3 + 3 + 1 + 1 + 1 hits (slim, global, why-tier, close-shape,
are-we-done); edited copy `/tmp/r2-C5/repo`: **0**.

### 4.2 Pinned anchors (python replay of the tests' own grep anchors, measured)

`python3 -I /tmp/r2-C5/bin/anchors.py /tmp/r2-C5/repo` (and `/tmp/r2-C5/core`): 11/11 PASS. It replays
`research-program-exemption-rules.bats` (slim F1, F2, close-question, E0, offering, research-F2; global F1,
offering, E0 row), the `wrap-ledger.bats` ladder parity anchor (`📦 > 🚀 > 👤` in global) and the
`cc-memory-search.bats` global anchor. None of the C5 edits touches a pinned span: S-b edits slim:146, the
pinned close-question line is slim:86 and the pinned offering line is slim:191.

Systematic pin scan (measured, `python3 -I /tmp/r2-C5/bin/ngram.py`): every 5-word window of every edited
span's OLD text, searched across all of `tests/` with whitespace normalized. Only two spans have any hits.
`nothing of mine is open; follow-on:` hits the fixture closes in `completion-assert.bats` (:2254, :2468,
:2529, :2546, :2578), and `<what remains + who owns it>` hits `completion-assert.bats:1684`, which quotes the
template as literal input. Both are **inputs**, not pins. Legacy closes that still use the old wording keep
parsing, because no matcher keys on the payload words (§4.4). Every other edited span has **0** hits, so no test
pins the text this set changes.

### 4.3 The one template source keeps its MENTION-vs-USE guard (measured)

`bash /tmp/r2-C5/bin/shape-probe.sh` sources the edited `hooks/lib/close-shape.sh` (pure functions, no hook
run, no state):

| input | `close_verdict_polarity` | `close_shape_missing` |
|---|---|---|
| `✅ Good to close: yes — nothing drivable is open; follow-on: none` + rung line | yes | (none) |
| `… yes — nothing drivable is open; follow-on: 1dcc10d88ee3 (the sealed test set, parked on data)` | yes | (none) |
| `❌ Good to close: no — six implementation waves in README §5 remain; I am driving wave 1 now` | no | (none) |
| `close_shape_template` itself | none | `good-to-close-verdict` (still a mention, as `completion-assert.bats:1660` requires) |

### 4.4 Payload wording chosen by measurement: `nothing drivable is open`, not `nothing drivable remains`

`scripts/drain-peer-findings.py` treats `nothing (of mine )?is open` as settled (`_SETTLED`) and
`remain(s|ing)` as an open tell (`_OPEN_TELL`). `python3 -I /tmp/r2-C5/bin/drain-probe.py` on the edited copy:

| close | `finding_of` |
|---|---|
| old payload, `follow-on: none` | `''` |
| **new payload `nothing drivable is open`**, `follow-on: none` | `''` |
| rejected `nothing drivable remains`, `follow-on: none` | `'✅ Good to close: yes — nothing drivable remains;'` (a false finding on every clean close) |
| the incident close | `"the implementation waves in README §5 haven't started, because this pass was research only"` |

So the obvious wording would have made the peer-findings drain file a row for every clean yes. The chosen
one keeps that tool's behaviour unchanged with no edit to it. Every other matcher that reads the S2 line was
checked by reading: `CA_YES_HEDGE` (completion-assert.sh:373) needs a hedge word right after `yes`;
`CA_RETRACT` is applied only to the text before the anchor on a verdict line (`:1258-1263`);
`close_line_reads_done` and `close_verdict_polarity` key on the glyph and yes/no; `dispatch-assert.sh`
`NAME_TELL` (:247) has no term in the new strings. No matcher keys on `who owns it` (grep: only templates,
docs and `completion-assert.bats:1684`, which quotes the template as literal input).

### 4.5 `--why` bodies stay substantive (measured)

`bash /tmp/r2-C5/bin/why-probe.sh`: hedge 196 words, shape 248 words (`why-tier.bats` P7 needs >= 40).

## 5. Constraint check

| # | constraint | how the set meets it |
|---|---|---|
| 1 | silent when nothing drivable remains | Text only; nothing fires. With no unfiled Gate-passing work, `✅ Good to close: yes — nothing drivable is open; follow-on: none` is exactly as reachable as before (polarity yes, shape complete, measured §4.3). |
| 2 | never blocks a ⛔ decision or a stated park | A filed `cc-decide` packet or backlog row is excluded by "unfiled"; a park (agent `clear` + named park, slim:20; operator pause, slim:49) and operator-owned items are routed to the rung by the clause S-b extends ("If something is parked or is theirs, that is the rung"). S2 is only required at ✅/👤 closes, so a ⛔ close is untouched. The operator's own "research only, do not implement" makes implementing a downside a reasonable operator would weigh (F1 FAIL), so that work is not Gate-passing. Nothing is blocked in any case: the effect of S-b is that the answer reads no. |
| 3 | no settings.json | None needed. |
| 4 | resident budget not grown | slim rules -16 (core) / -14 (core+D); global slim 0; `judge()` admits; control +1 is refused (§1, §3.3). |
| 5 | six owned files untouched | Files changed: slim rules, CLAUDE.global.md, hooks/lib/why-tier.sh, hooks/lib/close-shape.sh (template line only), commands/are-we-done.md, (D) commands/wrap.md. None is on the list. |
| 6 | one matcher per concept | No matcher is added or changed. `close-shape.sh` changes only inside the `close_shape_template` heredoc, so the template copies stay one wording. |

## 6. Should the close LEAD with what remains and who drives it? Is that already the ❌ form?

Yes, the ❌ form already does the leading. `❌ Good to close: no — <what remains + who owns it>` is line 1 by
contract (slim:22, slim:148 "first and never last"), and D6 `verdict-first` refuses a no under a done-reading
line 1. The census skeptic measured that since 2026-10-11, 315 of 329 yes closes are verdict-first and none
has a ✅ rung line above the verdict (axis 06, `q5.py`). The incident close led with its verdict too. The defect
was that the remainder went into the tail of a yes, which S-a and S-b now forbid. So any remaining unfiled,
Gate-passing work forces the ❌ form, and that work leads by construction. Adding a separate "lead with what
remains" clause would duplicate slim:22 and slim:148, and it would grow a tier that is already over budget.
**No new clause is recommended.**

On "owns" vs "drives": optional edit D is recommended. "Owns" can name an owner who is not acting, such as the
operator, "the plan" or "README §5". The census skeptic's hand-label (estimated) found about 54% of prose
follow-ons were hand-backs to the operator. "Drives" asks for the actor. An honest "nobody" or "me, later" then
visibly contradicts slim:103 ("Only ⛔, and 📦 in a repo whose own CLAUDE.md says landing spends money, may end
a turn holding work"). It also matches the "nobody drives" wording of S-b, so the yes-rule and the no-form use one
verb. Cost: +2 slim units, measured. It touches 10 places in 6 files, all listed in §3.2 and all applied and tested
in `/tmp/r2-C5/repo`.

## 7. What this set does not do (efficacy, estimated)

- **Continuation is not guaranteed.** An honest no is still a terminal-valid close (slim:148 "an honest no
  satisfies the contract"). The set makes the incident close read `❌ Good to close: no — six implementation waves
  remain …`, which meets the readability goal (INCIDENT Q4). Driving the waves still depends on slim:103, slim:105
  and F2, which already said to drive them and were violated. No text edit can force the drive. That needs a
  mechanism; other round-2 candidates cover it.
- **Efficacy is unmeasured.** No A/B of rule text was run. Running `claude -p` against a sandbox config dir could
  raise a Keychain or login prompt that nobody can answer, so it was not attempted. Estimated efficacy of this set
  alone against a repeat of the incident: **about 40%**. Method: the incident broke four rules that were already
  correct (F2 slim:68, slim:86, slim:105, slim:191), so text alone has a poor record here. Axis 06's skeptic also
  put only about 6-8% of prose follow-ons (10-13 of 158, hand-labelled) in the agent-drivable unstarted class this
  set targets. The rest of that 40% is my estimate that removing the only clause that licensed the shape, and
  changing the words the agent copies into line 1, does change some closes. That estimate is not a measurement.
- **The 06:03 "should we …?" stop is untouched.** It was a read-only turn with no S2 (axis 01 RC6).

## 8. bats runs against the /tmp copies

Queue: `bash /tmp/r2-C5/bin/suite.sh` runs, in order and serially, `research-program-exemption-rules.bats`
(full set, then core set), `why-tier.bats`, `drain-peer-findings.bats`, `cc-memory-search.bats -f
'CLAUDE|global|slim'`, `wrap-ledger.bats -f 'parity|control'`, `instruction-budget.bats` and
`completion-assert.bats`. The last includes four sandbox-only `C5PROBE` tests appended to the **copy**: the new
payload through the real hook via the suite's own `_cvf` harness, which is hermetic (`COMPLETION_STATE_DIR`,
`COMPLETION_IDL`, `CC_CUSTODY_DIR`, `CC_FIRED_DIR` and a backlog stub all live under `$BATS_TEST_TMPDIR`). Plan
line with the probes: `bats -c tests/completion-assert.bats` = 189. Each run goes through
`/tmp/r2-C5/bin/try-bats.sh`, which retries `cc-bats` every 20 s while it prints `REFUSED`.

**Admission.** From 20:15 local onward every attempt was refused: `cc-bats: REFUSED — 2 concurrent bats
execution root(s) (ceiling CC_BATS_MAX_ROOTS=2) AND 1-min load/core at or above CC_BATS_MAX_LOAD_PER_CORE=2.0`.
Two other sessions' suites held the slots (pids 42066 and 93212 from `.worktrees/lrwake-A`, 54 and 45 minutes old
at 20:54). `uptime` load averages rose from 138 to 335 on 10 cores. "Plain bats" does not get around this: the
PATH `bats` is a symlink to `cc-bats`, and `~/.claude/hooks/qos-rewrite.sh` deliberately rewrites any spelling
of a `bats` token, including `/opt/homebrew/bin/bats`, to `cc-bats` (header, transform (a)). The only override
is the waiver (`CC_BATS_WAIVER_REASON=… CC_BATS_MAX_ROOTS=0`), and it appends to
`~/.claude/state/bats-waivers.jsonl`, a live-state write this brief forbids. So I did not take it, and I did not
route around the rewrite hook. Results are recorded below as they arrive.
