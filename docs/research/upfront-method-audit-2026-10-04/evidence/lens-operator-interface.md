# Lens: the answerer and the operator interface

Auditor 2026-10-04, read-only. Question: does the method, as built, stop "are we complete?" → "oh, one more thing",
both inside a registered research program and in the common case outside one? Is the goal better served by changing
what gets SAID or what gets DONE?

Labels: **measured** = I ran it this session; **reported-measured** = a doc states a measurement I did not re-run;
**modeled** = simulation output; **asserted** = prose with no measurement.

## 0. Live state (measured)

- Registry: `~/.claude/autonomy/research/programs.json` holds one program, `truememory-2-0`, state `registered`,
  one `cwd_root` `/Users/chrisren/Development/.worktrees/tm2-plan`.
- `bash scripts/lib/research-program.sh is-active $PWD` (this worktree) => rc=1. `... is-active .../tm2-plan` => rc=0.
- The exemption text in the live `~/.claude/rules/10-session-close.md` is byte-identical to the repo's
  `CLAUDE.rules.slim.10-session-close.md` (`diff` => IDENTICAL). It is also in `CLAUDE.global.md:638-667`.
- Live hook registration (`jq` over `~/.claude/settings.json`; `~/.claude-next/settings.json` is a symlink to it):
  `PreToolUse [*] research-block.sh timeout=5`, `UserPromptSubmit research-precognition-nudge.sh timeout=10`,
  `Stop completion-assert.sh timeout=5`. Migrations 0050 and 0051 are in `~/.claude/autonomy/migrations/applied/`
  (0051 ts 1790913707, about 2026-10-02T04:01Z). Five `com.claude.research-*.plist` files are in `~/Library/LaunchAgents`.
- The live checkout and this worktree hold the same bytes for completion-assert.sh, research-block.sh,
  research-precognition-nudge.sh, hooks/lib/research-router.sh, router.py and research-program.sh (`cmp` => same, all 6).
- `bash scripts/research-kit/gate.sh --render --program truememory-2-0` => `Research: truememory-2-0 — registered; not
  certified. Certification rounds counted: 0; trailing quiet rounds: 0.`
- Load: `uptime` => load averages 69.47 72.88 83.73 on `hw.ncpu` 10.
- bats: `research-relay-check`, `research-router`, `research-program-exemption-rules`, `research-program-lib` all
  printed `cc-bats: REFUSED — 2 concurrent bats execution root(s) … load/core at or above 2.0`. That is **no verdict**,
  not a pass. I judged from code reads and direct probes instead.

## 1. What the SAID layer does today

Three layers (REPORT §4.1, §4.2 and §4.4) plus the rule exemption:

| Layer | Code | Active for the live program today? |
|---|---|---|
| Rule exemption (F1, F2, E0, close question, offering) | rules file :74-82, :86, :99, :191 | yes, in tm2-plan cwd only |
| D4 "offer" arm abstains | `hooks/completion-assert.sh:1108-1110` | yes, in tm2-plan cwd only |
| Re-ask router | `hooks/research-precognition-nudge.sh:33-44`; router.py `cmd_prompt` | **no**: routes only certifying/certified (nudge :43; `BLOCKING_STATES` router.py:73) |
| Tool block | `hooks/research-block.sh`; router.py:514-570 | **no**: `if state not in BLOCKING_STATES: return 0` (router.py:527-528) |
| Relay check (Stop) | completion-assert.sh:264-310 → router.py:638-658 | **no**: needs a RELAYED route record, which only certifying/certified write |

So for the only live program, the SAID machinery is the rule text plus one abstaining arm. The router, block and relay
check switch on at the freeze (`certifying`).

## 2. As built, the relay check fails open on a classifier fallback; gate row 15 scores fallback the other way

- `router.py classify` (lines 236-276) runs a cold `claude -p --model haiku` with a 6 s timeout. On error or timeout it
  returns None, and `cmd_prompt` records `label=unavailable` (router.py:354-359).
- On `unavailable`, `cmd_tool` denies only the research verbs (router.py:549-570). Other tools are allowed.
- The relay check returns 0 (allow) unless `route.label in RELAYED` (router.py:640). `unavailable` is not in RELAYED, so
  **the Stop relay check does not run on any fallback turn.** All that remains is the advisory context text
  (router.py:296-302: "If the prompt asks whether the work is complete, relay … add nothing").
- Gate row 15's scorer, `heldout.py evaluate`, does the opposite: `if got is None: fallbacks += 1; got =
  "completeness"` (heldout.py:216-218). So the reported completeness recall "14/14 · 3/3 · 1/1" (plan
  `docs/plans/RESEARCH_PROGRAM_BUILD.md:171-173`) credits fallbacks as relays, which the live router does not do.
  This is the "measure as built" defect: the instrument certifies the REPORT §4.1 design ("Routing fails closed …
  treated as a completeness question"), not the §10-item-3 behavior that was actually shipped.
- Fallback rate (reported-measured, plan :171-172): 0.96 at load about 295 and 0.51 at load 45-80. Today's load is
  69-84 (measured), which sits in the 0.51 band. Once tm2 enters `certifying`, about half of all re-asks would get no
  relay check, and at peak load almost all of them would. Row 15 already reads FAIL, and nothing stops the freeze from
  turning the block on with a known-failing router: gate rows run at stage 8, not at the freeze.
- Cause (reported-measured, plan :174-176): cold `claude -p` startup takes about 2 s at load 45 and about 5 s at load 295.

Recommendations:
(a) router.py:640: let the relay check also run on `label == UNAVAILABLE` when the reply opens with a completeness
verdict (reuse completion-assert's `CA_SETTLED`/`OPENS_NO`). A wrong fire costs one re-answer, capped at
`COMPLETION_RELAY_MAX=2`.
(b) heldout.py:216-218: score a fallback as `unavailable` and measure what the as-built hooks do with it, or require
row 15 to pass at the measured load band.
(c) Replace the cold `claude -p` with a warm or local classifier, such as a resident process or a small model trained
on the 96-item tuning set, so the fallback rate stops depending on machine load.
(d) Make the `freeze` verb refuse to set `certifying` while row 15 reads FAIL.

## 3. The relay check is lexical: it passes vague new items, passes a gamed "escape", and blocks the located real one

Measured by importing `router.relay_violations` with a sample certificate (the run wrote nothing):

```
A honest relay                     => PASS
B prose new item ("also a gap in how the migration ordering was checked") => PASS
C "One more thing: the hook isn't registered."                          => BLOCKED (ITEM regex)
D "No — I found that hooks/research-block.sh is not registered …"       => BLOCKED (path token + no EVENT word)
E "No — escape.\nThe auth flow was never reviewed and is broken."       => PASS
F "Yes. <cert>\nThough the vendor lane for Google never actually ran…"  => PASS
```

- The check tests the form of a reply, not its content. It blocks the located, checkable kind of new item (D), which is
  the kind REPORT §4.1 itself calls admissible as a concern. It lets the unlocated kind through (B, F), and that is the
  kind that produces "one more thing" without any way to act on it. `EVENT = re.compile(r"escape|freshness|accepted")`
  (router.py:587) is satisfied by the bare word (E).
- On a RELAYED turn the tool block allows only the bare certificate read (router.py:537-548, `cert_read` :495-504). So
  `cc-research concern add --program P --text … --raised-by agent` is denied, even though the verb exists and has an
  `agent` source (`cc-research concern add --help`). A real escape that the agent notices during a completeness turn
  therefore cannot be said and cannot be recorded. Nothing carries it to the next turn, and REPORT §4.4 makes agent
  concerns inadmissible by design.
- The census that motivated the check is weaker than the check's own justification suggests. REPORT §10 item 15 calls
  "20 of 73" a regex upper bound and puts the true hand-labeled count at about 2-3.

Recommendation: on a RELAYED turn, allow exactly one more tool: `cc-research concern add --program <slug>
--raised-by agent` (extend `cert_read` at router.py:495, or add a sibling whitelist). It writes only to the triage
queue, which never touches the reply or the certificate, and triage is already blind and scheduled (§5.2). This
changes what gets DONE (the observation is kept) without changing what gets SAID (the relay stays verbatim).

## 4. The exemption key covers one directory; the program spans seven

Measured (`is-active` against each tm2 worktree):

```
tm2-base        rc=1  origin TrueMemory                         last 2026-08-29
tm2-k3          rc=1  origin TrueMemory                         last 2026-10-02
tm2-plan        rc=0  origin claude-infrastructure-private      last 2026-10-04
tm2-plan-replan rc=1  origin claude-infrastructure-private      last 2026-10-02
tm2-slice       rc=1  origin TrueMemory                         last 2026-10-02
tm2-units       rc=1  (no git)
tm-upstream-wt  rc=1  origin TrueMemory
```

- `gate.sh register` takes exactly one `--root` (lib/gate.py:116 `cwd_roots=[a.root]`, :162 `--root required`), and
  no verb adds a root. The intake prefill itself says the root must never be the TrueMemory worktree
  (`tm2-plan/docs/research/truememory-2-0/intake-prefill.md:179-181`), and stages 3 and 5 run contact probes and the
  thin slice there.
- Result: the exemption claims to hold "from intake through build" (rules :74), but in the build sessions, the
  contact-skeleton sessions and the replan worktree the standing F1/E0/D4 rules apply in full. A completeness ask there
  gets a "no, one more thing" answer that is fully compliant.
- The router uses a second key that the exemption does not share. `rp_resolve_prompt` resolves a pane by the alias
  "tm2" named in its prompt (research-program.sh:150-175; nudge :40), but the D4 abstain resolves by cwd only
  (completion-assert.sh:1108). A pane routed by alias therefore gets "relay verbatim" from the router while the resident
  rules and D4 tell it to drive.

Recommendation: let `cwd_roots` grow. Add `gate.sh add-root --program P --root DIR`, and have `handoff-fire.sh
--requires-gate <slug>` register the fired worktree as a root, or key the exemption on the worktree's
`--requires-gate` marker as well. Give D4 the same prompt key the router uses.

## 5. Outside a program, which is the common case, the rules still force "no, one more thing", and the first "yes" is blind

- Rule text: "Outside an active program nothing changes" (rules :82). F1 "nothing left on the table" (:67), E0 "a
  read-only turn that names drivable work … drive the passes" (:99), and the close question "an open plan item is open
  work, so drive it or answer `Good to close: no`" (:86) all still apply. So do D4 (completion-assert.sh:1061-1077) and
  `anti-deference-nudge.sh`, which is registered on Stop. Every re-ask that finds anything yields "no, X; now driven".
  That answer is truthful. The defect is the earlier "yes", not the later "no".
- Why the first "yes" is blind (measured): `wrap-ledger.sh:637-690` computes REMAINDER as a count of unchecked `- [ ]`
  lines. The DoD store `~/.claude/autonomy/dod/` holds 76 `.md` files: **4 contain any checkbox, 75 contain a
  `Scope (frozen):` prose line.** That is the same "4 of 76" the REPORT diagnosed on 2026-09-30, unchanged. A prose
  scope line therefore gives REMAINDER=0 and SCOPE=met (`wrap-ledger.sh:697-699`) by construction. The ✅ rung and
  "Good to close: yes" are computed without ever checking the scope's content.
  `operator-readout.sh:1836` withholds the certificate only when SCOPE=unknown (no DoD), not when the DoD cannot fail.
- The re-ask then runs the audit the close skipped. Reported-measured: 268 of 280 asks (95.7%) called tools, about 20
  calls per ask, and 44 spawned subagents or Workflows (`evidence/adversary/llm/ask_turns.out:1-8`). The taxonomy:
  60% of holes were misses inside a frame the research already had, 11.5% (C1) were already known and on disk, and
  "the ask was usually the first adversarial audit" (`evidence/taxonomy.md:9-18`).
- The global rules forbid the obvious pre-claim cure. `CLAUDE.global.slim.md:178`: "no reflexive double-check pass or
  verify subagent over your own finished work". The REPORT's own finding (C8, plus bounded re-reads converging in 3-4
  passes, 10→7→2 and 7→1→0) argues the opposite for the terminal close of a planned task.
- The quota prompts the REPORT blamed ("Find 2-3 gaps") are fixed in the deployed agents: commit 7310c4ac8, and
  `agents/deep-research.md:187-188` now says "zero is a valid answer". That is a DONE-side fix that also helps outside
  programs.

Recommendations, all DONE-side:
(a) `hooks/dod-persist.sh` and the rules file :24 ("Freeze the DoD at intake") should capture the frozen scope as a
checkable list, with `- [ ]` items or acceptance commands. SCOPE=met (`wrap-ledger.sh:697-699`) should require at
least one checkable item, and a prose-only DoD should read `unverifiable`, not `met`.
(b) Amend `CLAUDE.global.slim.md:178`, and the matching line in `CLAUDE.global.md`. Before the first `Good to close:
yes` on a task that has a plan or a frozen DoD, run one bounded fresh-context review pass in which zero findings is
valid, only located findings count, and the program's RUBRIC.md materiality decides. The goal is to move the re-ask's
audit in front of the claim. The REPORT measured this as the first cause, and the method fixes it only inside programs.
(c) The close question (rules :86) and `/are-we-done` should list known residuals from the task's own stores (open
plan items, backlog rows linked to the plan, open decisions), not from the session ledger. That closes C1 outright.

## 6. The goal as stated is not physically attainable; the strongest attainable version, and an unsurfaced conflict

- The literal "never one more thing" cannot be reached. Modeled at measured inputs (calibration REPORT §1): the desk
  residual at signoff is 6.5-7.6 holes, the typical-case forecast is exceeded in 22-38% of programs, and the invisible
  share is 0.12. The REPORT gives 6-9 programs in 10 at least one material change after signoff (REPORT §1). Some of the
  rest cannot be reached by any desk method: reality moving (C10, 4%), genuinely new operator requirements (C2n, 3%), and
  new ideas in 17.7% of genuine prompts (REPORT §2.2 item 6).
- "As infinitely long as physically possible" makes things worse at measured inputs. More review produces more holes:
  Lite leaves 6.66 desk holes, Standard 6.45, Full 7.58. False material calls are about 1.1 per reviewer-read and
  fix-born holes about 0.21 per fix (calibration §1). Any profile reaches its hard cap in 93-100% of programs, so
  "infinite" collapses into the cap anyway.
- The operator's own rulings already settled this. Ruling 5: "'Infinite' means the program does not start". Ruling 8:
  "Freeze this method as version 1 with no further critique rounds … Change only named sections, from measured results"
  (REPORT §9). The restated goal of 2026-10-04 conflicts with both, and nothing in the interface surfaces that conflict.
  The method itself is not a registered program, so a re-ask about the method gets standard F2 handling: "research
  exhaustively", which is how this nine-auditor desk pass came about. REPORT §10 measured exactly that loop on this
  document: Chao1 rose from about 10 to about 42 between passes, and 12 of pass 2's 17 findings were born in pass 1's
  fixes.
- Strongest attainable version:
  1. zero known-but-unsaid items at signoff (C1 to 0, by listing every residual on the certificate);
  2. desk-findable residual pushed down by front-end and contact work, not by more reading;
  3. every later change pre-forecast with a bound, an owner and a date;
  4. no research re-triggered by asking.
- Said versus done: the evidence favors DONE. The relay can at best convert "one more thing" into "escape N of a
  forecast M", and as built it is mostly inert (section 2) or lexical (section 3). The levers that reduce what the
  operator actually experiences are front-end contact (REPORT §1: "the only things that shrink that number"), checkable
  scope (section 5a) and a pre-claim audit (section 5b).

Recommendation: register the method itself, and any program-level meta work, as a program, so that a re-ask about the
method relays its ruling 8 and its open-items table, and new ideas about the method park in v2. Alternatively, add a
rules line next to the exemption: a re-ask about something the operator froze by ruling is answered with the ruling
and its measured basis, plus the price of reopening, and is never answered with unasked research.

## 7. anti-deference-nudge has no program exemption

- `grep -l "research-program.sh\|rp_is_active"` over hooks/ finds only completion-assert.sh, hooks/lib/research-router.sh
  and scripts/wrap-ledger.sh. `anti-deference-nudge.sh` is registered on Stop. Its semantic arm (line 531) tells the
  model that a turn which identifies work and then yields is the E0 defect and must DRIVE it, and its lexical arm (line
  538) says "DRIVE it now".
- Inside a program, "refinements are filed, not driven" (rules :75). A program session that names a filed refinement
  with any deference tell is pushed to drive it. The rules text names only completion-assert's offer arm as exempt
  (rules :77).
- Recommendation: make `anti-deference-nudge.sh` source `research-program.sh` and abstain when `rp_is_active "$CWD"`
  and the message names an apply-at-build or parked id. Then extend the rules :77 sentence to cover it.

## 8. Strengths

- The registry key fails toward the standing rules. A missing registry, an unparseable one or a cwd outside every root
  all read as not-active (research-program.sh:24-31, :60-85). The exemption cannot spread by accident.
- The single-active fallback, which would have routed every pane to the one program, was deleted (§10 item 2;
  research-program.sh:26-27). That was a real cross-pane hazard.
- Exemption text is deployed identically in both variants. D4 abstains mechanically (completion-assert.sh:1108), and
  the abstain is logged with its slug (:1299). The block and the router are registered live. The certificate read is
  honest before certification ("not certified, 0 rounds").
- The router never sees the operator-only menu. It renders only in operator-readout (REPORT §4.2), so the model cannot
  turn it into an offer.

## 9. Minor stale text that misleads the operator

- `docs/plans/RESEARCH_PROGRAM_BUILD.md:256` says "Operator step left: `migrations/0051-research-jobs.sh`", but 0051 is
  in `migrations/applied/`. A stale ask aimed at the operator is a small "one more thing" of its own.
- REPORT §3.1 ruling 2, last line, says the exemption "is keyed on a marker in the program's DoD line". The code keys
  on the registry (research-program.sh:4-8). §3.1's slim line refs (`CLAUDE.global.slim.md:248, 259, 272, 364`)
  predate the split of the slim variant into two files (commit cbe90eb63).

## 10. Side cost (measured, minor)

Because the registry file now exists, `research-block.sh` forks `python3 router.py tool` on every tool call in every
session on the machine, including sessions in no program (`rr_registry_present` only checks that the file exists). That
costs about 0.09-0.11 s per call at load 70 (`/usr/bin/time` x3 => real 0.11, 0.11, 0.09).
