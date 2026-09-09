# A07 skeptic — caps, latches, exemptions, kill-switch (re-run 2026-09-08 ~19:00Z)

Read-only. Every number below is MEASURED here unless marked inferred. IDL reconstructed the report's
way (`cat idl.jsonl; gzcat idl.jsonl.*.gz`), parsed with a tolerant Python reader (the report's `jq`
dies at line 844,016 — see M1). Transcript populations: `tx-today.txt` = 477 files / 517 MB mtime<1 d;
`tx-30d.txt` = 2,125 files / 3.8 GB mtime<30 d across the four roots (realpath-deduped).

## What held

- KILL_RE at `session-continue.sh:224`; `last_user_msg` skips `isMeta` (:262); the "false positive merely
  allows one stop" comment at :277; `set` deletes `.count` (:117); block text at :1149; `clear` writes
  `${CC_MECH_MAX:-3}` (:149) vs reader `${CC_MECH_MAX:-2}` (:921); mechanical-assignee logged bare (:846)
  vs ship-floor-assignee with `confirm_rc` (:974); completion-assert per-class caps and bare
  `capped:N>=M` abstain (:1064-1079); anti-deference cap (:350); `CLAUDE.md:888` claim. All present.
- Binary (bytes.find, offset 164402088): `let Vd=a.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP??8;if(Vd>0&&qd>Vd)`;
  `ENABLE_STOP_REVIEW` / `STOP_REVIEW` / `stopReview` 0 occurrences; override message present ×2.
- `docs/research/final-response-shaping-2026-08-08.md:27,55`: `systemMessage` human-only, TUI-only.
- Hook-block feedback `isMeta=true`: **653 of 653** Stop-hook-feedback user records today.
- Longest consecutive block run with no genuine user record between: **311** (c262a75c), **236**
  (5a99940d), **206** (37940aef) — reproduced exactly; 3, 3 and 2 completion-assert blocks inside.
- Tool census today: Bash **25,276** vs Edit 328 + Write 117 = 445. Writers: bash-only **307**, both 64,
  edit-only 1, neither 105 → 82.5% of writer sessions invisible to `session-writes.sh`. Of 11,869 Bash
  write idioms, **4,521 (38%) target a `Development/`/`.worktrees/` path**, 4,494 `/tmp`, 2,854 other.
- IDL 11 d: `cap-reached` **0**; `fired continue` count field {1: 602, 2: 2, 3: 1}.
- `agent-identity.sh:46-63` cross-field walk is as described.

## What did not hold

**M1 — the report's IDL census is truncated.** `jq` aborts at line 844,016 (a 4 KB `autonomy-sweep`
record); the report's 58,950 hook records and every per-day count match my `jq` run exactly, i.e. it
inherited the truncation. Tolerant parse: **86,122** hook records; **565** completion-assert records lie
after the fatal line. Corrected: completion-assert cap trips **106** across **19** sids (report: 41/12);
`ship-floor-not-mine` **133** (90); `mechanical-assignee` **47** (38); completion-assert `kill-switch` 21
(19); `ship-floor-kill-switch` 8 (6). Direction of every claim survives; magnitudes are 1.3–2.6× off.
House rule: parse failures are verdicts, not noise.

**M2 — test fixtures leak into the live IDL.** 312 rows with `sid` `dbl-1/dbl-3/dbl-4`, cwd
`/var/folders/…/T/postland-run.*/bats-run-*/…`, ts 2026-09-08T08:55Z. They are **156 of the 605**
`fired continue` records. `tests/session-continue.bats:27-39` documents this exact leak being fixed
twice (2026-07-25, 2026-08-08 — CONTINUE_IDL); a postland-run test is leaking again.

**M3 — capped sessions and driven sessions are disjoint.** The headline ("checker goes quiet after 3;
driver runs 307 more") needs both in one session. In 11 d of IDL the 19 capped sids have **0**
continuation fires (one has 1); the sessions with ≥8 continuation fires (114cf9d5 220, 3cc1ccb7 93,
baedcd81 72, cd95af3e 36, b0bf12dc 10) have **0 cap trips** — 114cf9d5's completion-assert record is
216 `no-close-tell` + 4 `ledger-clean`. The three transcript chains the report cites (311/236/206) ran
2026-08-18…24, **before the IDL begins**, and have no IDL rows at all; "3 = COMPLETION_MAX" there is
inferred from block text, and the 220 chain (which IS in the IDL) shows the alternative reading —
the checker was not capped, it had nothing to say.

**M4 — the capped closes are largely honest ⛔ closes.** 158 completion-assert fires in 11 d: 93 on 🔧,
26 📦, **21 on ⛔**, 13 🚀, 3 ✅, 2 👤. Heaviest capped session c92b10b3 (23 trips, 04:31→06:34Z): its
three fires carry facts "BLOCKED ON YOU — 1 decision filed this session … that IS your rung", rung ⛔,
and the fired closes read *"⛔ Blocked — nothing on my side can move until those approvals happen.
Good to close: no — …"*; the 6 post-cap closes I read are the same shape (`⛔ Blocked — allow-list
decision bed4ce4ec791 open … Good to close: no`). The cap there suppressed **false positives**. The
report hand-read one session (41aaaa07), found the cap did no harm, and did not generalise the check.

**M5 — the 311 chain is an operator-attended session.** c262a75c (wt-sr-zerohuman, 2026-08-23/24) has
**36** genuine user records ("Silver platter me…", "Are we 100% complete…", "What is ToS?"). The 311
consecutive blocks happened between operator turns.

**M6 — the drain chain is not disarmed by a template line.** 5a99940d (recycle #28, the 236 chain) has one
33 KB genuine message with **no** kill match. Recycles #53/#55/#56/#103 match on body prose:
*"read `total footprint` and stop.**)"* and a quoted *"canonicalise both ends and stop"*.
`scripts/drain-brief.template.md`, `drain-brief.sh`, `drain-recycle-fire.sh`, `backlog.jsonl`,
`BACKLOG_DRAIN_24_7.md`: 0 hits for "stop expecting auto-background". The report's open question #4 is
answered: no one-line template fix exists.

**M7 — the kill-switch population is smaller and bursty.** Today: **0 of 477** sessions carry a kill
phrase in their last genuine message (2 hits in 869 genuine records; 48 isMeta-suppressed). 30 d,
two-stage scan (grep -l candidates → 482 valid files after losing ~180 to `xargs -P` interleaving, so a
LOWER bound): last-genuine-message kill hits **30** sessions (report 140), **23** writers (100), **17**
single-message (125); `and stop` followed by a word **17 of 51 = 33%** (report 50.3%); `just do not` 0.
Several last-message hits are team-lead `<teammate-message>` stop orders ("stop work, and stop running
suites") — correct disarms. Realized suppression in 11 d IDL: 21 + 8 logged abstains + an **unlogged**
mechanical-arm return (:826) — the report's "100 writer sessions with every rail off" is population at
risk, not observed harm, and the instrument to observe it does not exist.

**M8 — the brief-shaped matches are TERMINAL.** Fire briefs e66f15aa/4a8d5abc match on *"DO NOT
IMPLEMENT. Report and stop."*, *"…and STOP. Do not change `LegendItem`"*, *"report it and STOP."* — a
terminal-only regex (R1 half 1) leaves every one of these in place; only the exclude-the-brief clause
removes them, and those are real scoped stop orders the hook's own comment (:250-252) says SHOULD disarm.

**M9 — the population "6,131 transcripts / 84.3% single-message" could not be reproduced**: mtime<30 d
yields 2,125 files; among candidate files single-message is 232/482. Inferred: the report's corpus
includes older files and/or `agent-*.jsonl` sidechain files, so "125 single-message dispatched sessions"
conflates headless probes and subagent transcripts with dispatched sessions.

## Verdicts (detail in the structured output)

R1 refuted as specified (regex half inert on the measured brief shapes; brief-exclusion half reverses a
documented design and fails toward D-8 on unattended sessions) — 55%. R2 half-refuted (rc 2 ≡ rc 1 at
both consumers, mechanical arm unlogged; the path-extraction half is the strongest finding in the axis
but its fail-direction is mis-stated: git-status intersection does not stop over-attributing a sibling's
dirty file) — 70% for extraction, 0% for the rc change. R3 refuted — 30%. R4 half-refuted (IDL enrichment
yes; hook-minted backlog rows are refused by `cc-backlog add`'s class gate and are the cheap-entrance
pattern) — 60%. R5 holds — 95%, extend to the :826 kill return. R6 holds — 90%; `CLAUDE.md:502` also
needs the edit. R7 holds — 80%.

Commands: `idl.py`, `tx.py`, `tx2.py` in this session's scratchpad; grep/python one-liners inline above.
