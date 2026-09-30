# #36 step 1 — moment-of-action checks vs the four adherence misses

Date: 2026-09-28. Plan: `docs/plans/TRUEMEMORY_ADOPTION.md` § Wave E, row #36, **step 1 only**
("inventory the repo's existing moment-of-action checks … and map which of the four each would
have caught"). Step 2 (build a mechanism and run it through #35's harness) is not done here: it
needs the operator box (live transcripts, `claude -p`, an account) and #35 showed the harness needs
tasks the stock arm fails first.

Method: read-only, on a trunk-equal checkout (`git rev-list --count HEAD..origin/main` = 0 at
`ea07499f`), from a cloud VM. What I ran: the hook header comments in `hooks/*.sh`, birth commits
(`git log --diff-filter=A`), registration migrations (`migrations/0027-*`), and a grep over `hooks/`
for outbound-message and sign-off predicates. **Not seen:** the live `~/.claude/settings.json`
(which hooks are registered today) and any repo-local hooks in `reso` or `personal`. #79's
sign-off rule lives in reso's `.claude/rules/bottle-generation-ledger.md`, so a reso-side check
could exist and this inventory cannot see it.

## The four fixtures (from `gap-2.md` §1)

| # | miss | the moment of action | action surface |
|---|---|---|---|
| #10 | draft sent from a stale/partial read of the WhatsApp thread (`bin/wa` newest-first + `tail`) | composing the draft | assistant TEXT (the draft), after a Bash read |
| #11 | "balance cleared before account closes" implied nothing was due later | composing the draft | assistant TEXT |
| #29 | handed the operator a command the agent could run | the close / hand-off | assistant TEXT at Stop (`▶ Run this:`) |
| #79 | agent treated work as signed off when only a human may sign off | the close / done claim | assistant TEXT at Stop |

All four are text the agent writes. None of them is a tool call, so no PreToolUse guard sees them.
Only a Stop hook, or a PostToolUse hook on the READ that comes before the draft (#10), can act at
the moment.

## Inventory — the moment-of-action checks that exist in this repo

| check | event | what it fires on | born | #10 | #11 | #29 | #79 |
|---|---|---|---|---|---|---|---|
| `hooks/handoff-claim-assert.sh` (+ `bin/cc-cannot`, `bin/cc-owner`) | Stop, block on REFUTED only | a `▶ Run this:` marker whose command `cc-cannot` refutes as agent-runnable | `cc492538` 2026-09-12; registration is c10 migration `0027` | — | — | **yes, from 09-12** (the miss was 09-09, 3 days before the hook existed; that miss is part of what it was built from) | — |
| `hooks/completion-assert.sh` | Stop, block once | a done or soft-close assertion that the LIVE ledger contradicts (dirty tree, unlanded commits, DoD remainder) | `a5f8314c` 2026-07-18 | — | — | — | **no**: #79's contradiction is a missing human act, not git state. A clean, landed tree passes |
| `hooks/anti-deference-nudge.sh` | Stop | deference tells ("want me to", "shall I") or a done claim plus a ledger contradiction | `b9b2804f` 2026-07-17 | — | — | partial: it catches offers, not a hand-off marker | — |
| `hooks/dispatch-assert.sh` | Stop | follow-on work named in prose but never written to the backlog | `2fdfa7da` 2026-07-25 | — | — | — | — |
| `hooks/operator-readout.sh` | Stop, advisory `systemMessage` | renders operator steps from disk; never re-prompts the model | `652f66db` 2026-07-20 | — | — | — (it informs the operator only) | — |
| `hooks/relay-verbatim.sh` | PostToolUse(Bash) | a canonical renderer ran, so its output must be pasted verbatim | 2026-08-01 | closest pattern: this is the event and shape #10 needs, keyed on `bin/wa` reads | — | — | — |
| `hooks/enforce-email-formatting.py` | PreToolUse (mail send) | email body formatting | — | no: format only, and #10's channel was WhatsApp | — | — | — |
| #6 lesson pointers (`hooks/lib/lesson_recall.py` via `bash-output-offload.sh`, `log-bash.sh`) | PostToolUse / PostToolUseFailure | lesson-symptom literals in tool output (`scripts/lesson-symptoms.tsv`) | Wave B `4a5b11919` | could, if a `bin/wa` newest-first symptom row existed; none does | — | — | — |
| `hooks/cc-unattended-ask-guard.sh` | PreToolUse(AskUserQuestion) | a blocking ask when nobody is watching | — | — | — | — | — |

A grep of `hooks/` for `whatsapp`, `bin/wa` and `wa send` finds no match. The only sign-off
predicate in `hooks/` is `completion-assert.sh`'s "offer lines removed" carve-out (`:82`, `:984`),
which exists to stop sign-off *politeness* from firing it.

## Map — which fixture miss each existing check would have caught

| fixture | caught today by | verdict |
|---|---|---|
| #29 | `handoff-claim-assert.sh`, if migration 0027 has run on the account (the operator box holds that fact, this VM does not) and if `cc-cannot` returns REFUTED for that command | **covered** (conditional on registration) |
| #79 | nothing in this repo | **uncovered**. The rule is resident. What is missing is a Stop predicate that reads "signed off / approved / baked" in the close and cross-checks a human sign-off record. completion-assert has the right shape (done claim × record contradiction) but checks the wrong ledger |
| #10 | nothing | **uncovered**. The cheapest candidate is a PostToolUse(Bash) row on `bin/wa` reads, the relay-verbatim/#6 shape, that pushes "output is newest-first; `tail` shows the OLDEST; re-fetch before each draft". That is also a #6 symptom-table row, so it needs no new hook, only a row plus the `bin/wa` literal |
| #11 | nothing | **uncovered, and no cheap mechanism exists**. It is a semantic composition error in a draft, and no literal predicate sees it. It is a candidate for #36's pre-registered ≤10% false-block budget only with a model-graded check, which is out of step 1's scope |

**Step-1 tally: 1 of 4 covered (#29), and conditional on registration. 0 of 4 are covered by a
check that existed before its miss.** For step 2, the pre-registered bar is "prevents ≥3 of 4".
Two mechanisms are cheap and literal, a `bin/wa` symptom row (#10) and a sign-off × ledger Stop
predicate (#79). Together with #29's existing hook they reach 3 of 4 on paper. Only #35's harness,
with tasks the stock arm fails, can say whether they work. #11 is the one that needs a
non-literal check.

## What step 2 needs that this VM cannot supply

- The live `settings.json` Stop list, to confirm 0027 ran (`migration-verify` line in
  `migrations/0027-handoff-claim-registration.sh`).
- A reso checkout, to check whether a repo-local sign-off guard already covers #79.
- The #35 harness run on an account, with fixture tasks built from these four transcripts
  (`gap-2.md` §0, `sessprobe.json`).
