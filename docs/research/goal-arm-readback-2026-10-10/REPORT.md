# Goal-arm read-back: why a healthy composer read as "<unreadable>" (2026-10-10)

**Answer.** `composer_content` read only the last 24 rows of the pane. A long `/goal` in a narrow pane
wraps the composer taller than that, so its top border fell outside the window, the parse found one
border and returned UNKNOWN, and `it2_paste_submit_verified` reported `saw '<unreadable>'` and withheld
the CR over a composer that was fine. The fix reads a bigger window only in that one shape and accepts
the box only if it is shaped like a composer, so a modal still reads UNKNOWN and gets no Enter.
Landed in `373bb4230` (plus the commits named in the plan).

Method: a 5-slot Dynamic Workflow (forensics, modal fail-closed, sibling copies, residue/notify, skeptic),
read-only `workflow-lean` slots writing `slot-*.md` beside this file, plus the lead's own live
reproduction. Four slots died once on a network outage (ENOTFOUND) and were re-run from the cached run.

## Q1. The exact reason each mangled arm read "<unreadable>"

**Measured live on pane 203** (the lead's own pane, 32 columns × 62 rows, mid-turn with a spinner up):
the 472-char `/goal` wraps to 22 composer rows; with the 3-row footer under the bottom border, the top
border is 26 rows from the bottom. `composer_content` gives rc 1 at 24 and 25 rows and the exact payload
(472 stripped chars) at 26 and above. Captured screen: `evidence/pane203-midturn-32col.*.txt`, home
path rewritten. The operator's screenshot of pane 202 (same width, 21 composer rows) is the same shape.

All 5 `mangled` rows in `~/.claude/logs/handoffs.jsonl` say `saw: <unreadable>` (panes 70, 175, 176,
202, 203); fleet tally at research time 47 set · 5 mangled · 3 unverified. Per-row geometry:
`slot-forensics.md`.

Hypotheses (b) mid-turn rendering and (d) timing are not needed: the pane-203 capture was taken
mid-turn and parses correctly at 26+ rows, and eight polled read-backs all failed the same way, which a
timing race would not do. (c) wrong region is the root cause in a precise sense: the region was right
(the bottom of the screen) but too short.

## Q2. The smallest change that reads a healthy composer and still refuses a modal

Design D1, in `composer_content` and in `lr-fire-resume.sh`'s `LR_SCREEN_SH`:

- The 24-row read stays the common path, byte for byte.
- Only when that window holds a bottom border and no top border is a bigger window read
  (`FIRE_COMPOSER_READLINES_MAX`, default 200; `LR_SCREEN_LINES_MAX` in lr-fire-resume). On kitty, CC
  panes are in the alternate screen, so `--extent all` returns exactly the visible screen; a bigger N
  cannot reach stale scrollback (measured, `slot-siblings.md`).
- The box from the bigger read counts only if: (i) its bottom border is the same row, counted from the
  bottom; (ii) its top border is a rule at column 0; (iii) its first row starts with the prompt glyph
  `❯`; (iv) every later row is blank or two-space indented; (v) no dialog selector (`❯ 1.`) sits under
  the bottom border. Anything else stays UNKNOWN.

Why not just widen the window (D2/D3)? Over 2,112 captured close-guard snapshots, a widened window
without shape checks changes one verdict: `win527`, where a teammate shutdown panel (`╭──╮`) above the
composer is read as 586 chars of "draft". D1 rejects it at (ii). The whole-screen copies (`cc-tui.sh`,
`lr-composer-snapshot.sh`, `bin/it2-kitty`, `lr_recon/observe.py`) already read the full screen and are
not affected by this bug; they keep today's win527 misread, which is non-empty and therefore holds rather
than types (`slot-siblings.md` §4).

Evidence the fail-closed property survives:
- Corpus replay, old vs new `composer_content` over 997 composer snapshots in
  `~/.claude/logs/composer-snapshots`: 0 verdicts differ. The siblings slot's prototype over 1,056
  unique snapshots: 117 reach the re-read, all 117 are rejected.
- Every real modal fixture in the repo (`tests/fixtures/lr-recon/screens`: trust, settings error,
  background-work dialog at 29/40/80 columns, resume pickers) plus win527, alone and under a hostile
  transcript built to fool the widened read (a column-0 rule, an echoed prompt shaped like a composer
  holding the payload, then the modal), never reads EMPTY and never matches the payload, in both copies
  (`tests/composer-tall-readback.bats`).
- Each shape check is shown load-bearing by breaking the box one way at a time.

Skeptic findings and residual risk: `slot-skeptic.md`; modal catalogue: `slot-modal-failclosed.md`.

## Q3. Should an unsubmitted /goal be cleared or retried, and by what path?

**Cleared, not retried** (`slot-residue-notify.md`). A `/goal` starts a turn the moment it is submitted
and installs a Stop-blocker; submitting it later into a session whose state is unknown is worse than
not arming. The eight-try poll at the arm site is the retry, and once the read is fixed it covers the
measured cause (5 of 5). The scrub at the mismatch site is the clearing path, where attribution is free.

The residue-receipt mechanism did not work for goals: the unreadable branch recorded the literal
`<unreadable>`, and `composer_residue_is_ours` compares byte for byte, so 7 of the 8 receipts on disk
could never authorise a later scrub. Fixed: that branch now records the pasted text (stripped as the
read is), and the scrub-off branch records the whole read instead of a 120-char cut.

## Q4. Should the operator be told in the firing pane and in the fired pane?

Both were already told on a fresh fire (stderr in the firing session's transcript; a cc-notify inbox
line to the fired session). Three gaps, all fixed:
1. The fired session's line was written for a human ("press Enter"); a model has no keyboard. It now
   says the session runs WITHOUT the goal backstop and must drive its brief to the end state itself.
2. The messages said the text "sits UNSUBMITTED" even when the scrub had just cleared it, which after
   this fix is the usual outcome. `FIRE_PASTE_SCRUB` now carries what is left, and every message says it.
3. On `--recycle` nobody was told: the firing session is the one replaced. The desk is now paged once.

`commands/handoff.md` § Autonomous fire item 1 now lists every verdict the code emits
(`set|unverified|abstained|held|mangled|unreachable`).

## Debris left by the incidents

Panes 202 and 203 held unsubmitted `/goal` text at research time (203's was later submitted by the
operator). The old `<unreadable>` receipts are inert: they match nothing, so they authorise nothing.
