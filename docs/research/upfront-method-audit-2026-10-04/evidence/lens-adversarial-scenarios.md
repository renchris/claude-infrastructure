# Lens: adversarial scenarios — where "one more thing" still reaches the operator after the method certifies

Auditor: one of nine independent lenses, 2026-10-04. Read-only. Worktree `wt-cc-024434-55635` at `008330afe`.
Subject: method v1.1 (`docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`) and the kit as built
(`scripts/research-kit/`, `scripts/lib/research-program.sh`, `hooks/research-*`, `hooks/completion-assert.sh` ARM R).
Live program used as a test bed: `truememory-2-0` (records `~/Development/.worktrees/tm2-plan/docs/research/truememory-2-0`,
a symlink to `truememory-2.0-2026-09-28/program`), state `registered`, Stage 4 open.

Labels: **measured** = a command I ran this session; **read** = code or doc read at file:line; **modeled** = a scenario
I constructed and traced but did not observe happen.

## 1. What I ran (receipts)

| # | Command (read-only) | Output (abridged) |
|---|---|---|
| M1 | gate rows 1,3,4,5,7–14,16 evaluated in-process on TM2 (no row that executes census/acceptance commands, no row 15) | 1 PASS · 3 PASS · 4 FAIL (17) · 5 FAIL (16 open decisions) · 7 FAIL ("interactive-zsh / launchd-bash32 never crossed", "3 environment(s) from the doctor") · 8 FAIL (155) · 9 FAIL (not frozen) · 10 FAIL (23) · 11 PASS · 12 FAIL (11) · 13 FAIL · 14 FAIL · 16 PASS |
| M2 | `numberless_superlative()` (gate_rows_a.py:64-68) on 7 sentences | **False** for "The deliverable is the 100th percentile absolute perfection implementation.", "Reach 100.00/100.00 correct, covering, and complete.", "Search must be maximally fast.", "Recall must be flawless on all 3 hosts.", "Ranking is optimal and complete with zero gaps.", "Nothing can beat it." |
| M3 | `router.relay_violations()` (router.py:608-635) on 4 replies to a completeness ask | plain-prose new item "Separately: the published wheel ships the maintainer API token in plain text; rotate it now." → `[]` (passes) · same finding with `truememory/config.py:41` → blocked · stock "One more thing worth flagging…" → blocked · pure relay → `[]` |
| M4 | `bash scripts/lib/research-program.sh resolve-prompt "<p>"` | "Is TrueMemory done and complete?" → `[]` · "are we 100.00/100.00 on the truememory upgrade?" → `[]` · "is the memory PR for Josh ready?" → `[]` · "is tm2 complete?" → `truememory-2-0 registered` |
| M5 | `research-program.sh resolve ~/Development/.worktrees/tm2-slice` | empty (rc 0). Sibling TM2 worktrees on disk: `tm2-base tm2-k3 tm2-plan tm2-plan-replan tm2-slice tm2-units`; registry `cwd_roots` = `[tm2-plan]` only |
| M6 | TM2 `frame.json` fac_map / credentials | 33/33 mapped, 0 N/A. FAC-07 → `PR-09`, FAC-23 → `PR-01`, FAC-25 → `PR-04`; `credentials`: None; `build_window_end`: None |
| M7 | TM2 premises | 90 premises, 89 load-bearing, **0 without `recheck_cmd`** |
| M8 | `/usr/bin/find` md files | records dir top level: 4 md (FRAME.md excluded by row 8 → 3 traced); sibling `truememory-2.0-2026-09-28/` outside `program/`: **206 md, 1,748 headings** |
| M9 | `grep -n '^BASE\|U_HI' scripts/research-kit/estimate.py` | `BASE = dict(u=0.05, fpp=0.01, q=0.05, omit=0.3, …)`, `FIX_BORN, U_HI = 0.1, 0.2`; no read of `params-measured.json` anywhere in `scripts/` or `bin/` |
| M10 | `grep -rn -i 'safety\|security\|hazard' scripts/research-kit/lib/*.py scripts/research-kit/*.py` | only the strategy name `operations-and-security` (kit.py:98) and the keychain binary `/usr/bin/security`; no safety bucket, no safety pause |
| M11 | TM2 intake | `intake-answers.md`: "The operator's answers to the 12 interview questions … given in pane 83 through two multiple-choice prompts built from intake-prefill.md"; exclusions' `operator_words` = "Confirm the list (Recommended) — intake answer 5" |
| M12 | `head replan_holes.py` (TM2) | "Rounds 24-29 ran on tm2-plan-replan … after the candidate 29122eec3 was frozen for the program, so they are outside-loop plan critiques, not program rounds. The 60 distinct rows …" |
| M13 | TM2 known rows | KR-01: census P3 found a 9th adapter (chatgpt) the frame named 8 of; KR-02: census P10 found the json1 axis the frame omitted |

## 2. Scenarios

Each scenario: origin (taxonomy hole id or repo history) → trace through stages and gate rows → verdict.

### S1. The operator asks "are we done?" in a build-wave pane (C1 relabel; holes 1, 13, 169) — SLIPS
- History: hole 1 ("Good to close: yes" on a wave, then "a quarter of the way there"); limit-detect "0 of 7 waves built"
  (REPORT §2.3 ex. 1). Build waves are where post-signoff items surface.
- Trace: build waves fire with `handoff-fire.sh --requires-gate <slug> --worktree <new>`; nothing adds the new worktree
  to `cwd_roots` (only `gate.py:116` `cmd_register` writes them; grep of `handoff-fire.sh` for `cwd_roots` → 0).
  The resolver matches `"$croot"|"$croot"/*` only (`research-program.sh:92-93`), so `tm2-slice` resolves to nothing (M5).
  Consequences in that pane: (a) the router branch does not run unless the prompt names the slug or an alias, and alias
  matching is per prompt (plan B1 "a pane that named the program once is ordinary again on its next prompt"); M4 shows
  "Is TrueMemory done and complete?" is unrouted because the alias is "TrueMemory 2.0"; (b) the standing-rule exemption
  is keyed on `is-active "$PWD"` (~/.claude/rules/10-session-close.md, Active research program exemption), so the
  close-question rule ("an open plan item is open work, so drive it"), E0 and the D4 offer arm apply in full;
  (c) `wrap-ledger.sh:824` resolves `RESEARCH_PROGRAM` from `$PWD` only, so the "two verdicts" fix for C1 (§8 item 13)
  reads `none` there.
- REPORT §3.1 says the exemption holds "from intake through build". As built it holds only inside one directory.
- Verdict: **slips undetected**. No gate row checks where build waves run; the relay test (row 14) names the program
  by alias in its outside-the-root trial (`cli_cert.py:377-419`), which is exactly the case that works.

### S2. A sibling worktree researches the certified topic (C6 duplicate lead, hole 139; TM2 replan) — SLIPS after the certificate
- History, real and current: TM2 ran critique rounds 24–29 on `tm2-plan-replan` after the program froze its candidate,
  60 distinct rows "outside-loop" (M12); the program absorbed them by a hand script. Before the certificate this was
  caught by hand. After it, the same session would sit outside `cwd_roots` (S1 mechanism), the research block
  (`router.py:526-528`) would never engage, and an open review ("review the truememory plan") runs unblocked.
- Row 8's topic-owner check is `if not (ctx.frame.get("topic_owner") or "").strip()` (gate_rows_a.py:525): a non-empty
  string, not the "positive sign of life" or exclusivity REPORT §3.2 step 1 requires.
- Verdict: **slips**; its findings return to the operator as new items outside every counter.

### S3. The classifier is slow, so the re-ask lands on the `unavailable` path — SLIPS (measured fallback rate)
- Measured in the plan (RESEARCH_PROGRAM_BUILD.md:171-176): fallback 0.96 at load ~295 and 0.51 at load 45–80 against
  the 6 s limit; row 15 FAILS.
- Trace: `unavailable` denies only research verbs (`router.py:563-566`; plan B1 "concern, other and unavailable deny the
  research verbs only"). The Stop relay check returns 0 for any label not in `RELAYED` (`router.py:640`). So on the
  most likely path under load, layer 2 (all-tool deny) and layer 3 (Stop check) are both off; the agent may Read/Grep
  and is only *told* "relay these lines verbatim and add nothing" (`router.py:296-302`).
- REPORT §4.1 and §4.2 had a fail-closed design (timeout → completeness). §10 item 3 relaxed it to avoid an all-tool
  lock; the relaxation is reasonable, but it removed the Stop check too, and no row measures what happens on that path.
- Also: with row 15 FAIL, `gate.sh run` can never issue a certificate today (`gate.py:148`), so the method cannot
  reach its own end state until the router is fixed.
- Verdict: **slips** on the unavailable path; the certificate path itself is **blocked**.

### S4. The agent volunteers a paraphrased "one more thing" in a completeness turn (§2.2 cause 3) — SLIPS
- M3: a new item written as plain prose of ≤3 lines passes `relay_violations`; only code-styled tokens, paths,
  `file:line`, ids and a stock phrase list (`ITEM`, router.py:580-585) are caught. "Separately", "Also note", "Heads-up",
  "I'd add" are not in it.
- The 3-line allowance (`MAX_EXTRA_LINES = 3`, router.py:601) is exactly the room a new item needs.
- The latch abstains after 2 blocks per session (`completion-assert.sh:295-300`, `COMPLETION_RELAY_MAX` default 2).
- Verdict: **slips**; REPORT §4.4's guarantee ("blocks any reply that names an item … whether it opens yes or no") is
  lexical in code.

### S5. A late security / data-integrity finding (§3.11 clause f) — partly SUPPRESSED, partly leaks
- Completeness turn: the same M3 test shows the precise, located form ("`truememory/config.py:41` writes the API token
  world-readable") is **blocked**, while the vague form passes. Every tool but the certificate read is denied, so the
  agent cannot file a concern in that turn either.
- Admissibility: REPORT §4.4 admits concerns only from a pre-registered detector or an operator prompt with a location;
  an agent that notices a hazard by reading has no admissible channel. The code is looser (`RAISERS` includes `agent`,
  cli_records.py:29) but triage has no safety route: the 13 buckets (cli_records.py:32-61) contain no safety bucket,
  and "immaterial" is paraphrased as "true, but changes no decision, check or plan line" — clause (f) ("always
  material: stop and surface", RUBRIC.md:17) is not in the rater's brief. One rater, daily batch (`triage`,
  cli_records.py:489-538).
- §5.3 step 2 "a safety-class escape pauses … build waves" is not implemented (M10: no safety in the kit).
- Gate row 16 FAILs on a third agent-originated change request regardless of severity (gate_rows_b.py:392-398,
  cap 2) — a perverse incentive not to file.
- Mitigation that exists: build-wave turns are work orders with normal handling, and the slim rules' "Security or
  data-integrity issues: stop and surface now" is not exempted.
- Verdict: **delayed or buried, not prevented**; the operator hears it late, and possibly not as urgent.

### S6. A checklist axis is "mapped" to a row that does not cover it (C4/C10; hole 96, Fly token caveat expired) — SLIPS
- M6 on the live program: FAC-07 ("what expires, who re-authenticates") → PR-09 "An upgrade never re-runs setup, so
  host-config strings are a permanent contract"; FAC-23 ("sibling trunk activity, registry releases, credential
  validity") → PR-01 "Upstream main is still 063e5b8"; FAC-25 ("compliance and data residency") → PR-04 "The
  contributor-agreement text is CONTRIBUTING.md:293-308". Intake Q2 ("what expires") was answered by the prefill
  "host-config strings are a permanent contract" (M11).
- Row 1 accepts any non-empty `row` string (gate_rows_a.py:126-133); it does not check that the id exists or that it
  addresses the axis. `frame.credentials` is absent, so row 10's credential loop iterates zero times and passes
  (gate_rows_b.py:146-158). `grep -c 'FAC-07\|FAC-23\|FAC-25' holes.jsonl` → 0: no frame-critique finding touched it.
- Modeled consequence: a PyPI/trusted-publisher or host-login lifetime, or user memory text leaving the machine to a
  hosted model (PR-77 prices OpenRouter models), surfaces at release. Triage would call it an **escape** (a checklist
  row covers the axis) — so it is counted, but nothing upstream caught it.
- Verdict: **slips the gate; counted only after it surfaces**.

### S7. A known item sits in prose the reconciliation does not read (C1 hole 169; C6 holes 61, 123) — SLIPS
- Row 12 reads plan lines matching `TODO|TBD|- [ ]`, residual rows, open decisions and dirty files
  (gate_rows_b.py:215-231). REPORT §3.7 step 3 and row 12 also name research residual sections, backlog and custody;
  none is read. "Known gaps", "open items", "deferred", "not yet" in prose are invisible.
- Row 8 traces headings of top-level `*.md` in the records dir only (`ctx.records.glob("*.md")`, gate_rows_a.py:492)
  and no claim sentences at all, though §3.7 step 2 says "every heading and claim sentence". On TM2 that is 3 files,
  against 206 md files and 1,748 headings of the program's own prior research beside it (M8) and the replan branch's
  KNOWN-GAPS.md (M12).
- Verdict: **slips**; the C1 "re-rendered as new" loop survives through stores the gate does not read.

### S8. The operator's superlative enters the frame (C11, holes 11, 56) — SLIPS the lint
- M2: the lint passes any sentence containing a digit, so "100th percentile", "100.00/100.00" and "on all 3 hosts" are
  exempt; `\bmaximal\b` misses "maximally"; "optimal", "complete", "zero gaps", "nothing can beat it" are not in the
  list. The operator's verbatim goal for this audit passes.
- Verdict: **slips the lint**; caught only if a frame-critique reviewer flags it (desk-detectable, inside the bound).

### S9. The operator asks in a frame the rehearsal never typed (C1 frame shift, §2.2 cause 6) — COUNTED late
- `intake.py:86` hard-codes `HISTORICAL_FRAMES = ["deployed and live", "nothing can beat it", "no loose ends"]`; row 14
  requires only those to be typed (gate_rows_b.py:323-328). REPORT §3.8 says twelve sessions, and §2.2 records new frames
  "no take-backs" (09-16), "end-game" (09-17), "left on the table" (09-30); today's goal adds "correct, covering".
- The router still relays the certificate for any wording (good); what is lost is the rehearsal's material finds under
  those lenses. A find later is a "frame defect" (counted on line 1).
- Verdict: **counted, not prevented**.

### S10. "Is it deployed and live?" after the certificate (C1, REPORT §2.3 ex. 1) — answer is unresponsive
- `lines_for` (gate_cert.py:191-234) renders a research certificate: no "Built 0/N · Live –" line and no "Scheduled
  checks" line (both shown in REPORT §4.3), and "take-backs 0" is a literal string (gate_cert.py:213). The observed
  "material changes after signoff, any cause" counter (§5.2) is never rendered. The certificate is written once and
  re-rendered unchanged until a re-issue.
- So a completeness ask about deployment gets a verbatim research certificate and nothing else (relay check). The
  operator learns the live state later — the hole-1 pattern again, now enforced.
- Verdict: **slips** (by construction of the render).

### S11. The forecast is lower than the method's own measurements (calibration) — COUNTED, mis-forecast
- The certificate's forecast uses `estimate.forecast()`, whose invisible part is `n_hat * BASE["u"] / (1 - BASE["u"])`
  with `u = 0.05` (estimate.py:36, 329). Calibration measured u = 0.12 (REPORT §3.12 table) → the printed invisible
  mean is 0.053·n̂ instead of 0.136·n̂, about 2.6x low (modeled from the two constants). R_max's p90 is simulated with
  `fpp = 0.01` against a measured 0.22–1.13.
- The forecast covers desk and invisible holes only. Operator intent (C2, 6% of the 200), drift (C10, 4%), realized
  residuals ("No (budgeted)", §5.2) and undeclared contact holes are counted elsewhere or not at all — each is still a
  "one more thing" to the operator.
- Verdict: **counted, but the printed promise is smaller than measured reality**.

### S12. The expected count itself (all classes) — COUNTED AND FORECAST, by design
- At measured inputs the stop rule cannot fire: every profile reaches its hard cap in 93–100% of programs; lite at 20
  holes leaves 6.7 desk + 3.0 invisible ≈ 9.7 material changes after signoff (REPORT §3.12 calibration table,
  `sim-main-fa022.out`; §6.1). The cap round's finds become named known rows applied at build.
- So the method, honestly run today, forecasts on the order of ten post-signoff material changes per program. It
  converts "one more thing" from a surprise into a printed number; it does not remove it.
- Verdict: **counted and forecast**; this is the central goal mismatch (see §4).

### S13. Contact claimed on a stand-in (C9, holes 153, 170) — partly SLIPS
- Row 7 checks only environments the doctor found on *this* machine (gate_rows_a.py:401-414; M1 "3 environment(s)").
  TM2's consumer runs "on users' machines under each host's hook runner" (frame.consumer) with 9 hosts and OS×Python
  3.10–3.14 (census P3, P5); those are not environments row 7 knows.
- The scheduler check only applies to `dict` components with `scheduled: true`; TM2's 8 components are strings
  (`['str', …]`), so it can never fire there. Where it does fire, any one successful launchd-bash32 skeleton probe
  satisfies every scheduled component (`any(...)` at gate_rows_a.py:417-422 is not keyed on the component).
- Liveness is required only when a cell carries a `properties` key (gate_rows_a.py:449-455).
- TM2 did declare R-K11-live (hosts without a login) as a residual with a falsifier — good — but a realized residual is
  "No (budgeted)" in §5.2, so the operator hears it and no counter moves.
- Verdict: **partly slips, partly declared-and-uncounted**.

### S14. The operator's "confirm" is the intake (C2u, holes 36, 107, 194, 198) — COUNTED as parked
- M11: 12 interview questions answered through two multiple-choice prompts built from the agent's prefill; exclusions'
  "your words" are "Confirm the list (Recommended)". Row 3's `exclusion_quote` and the frame's `operator_words`
  accept that.
- When a never-volunteered intent surfaces (hole 194, "in-person agreement with the author", is a TM2 hole), triage
  sees "an intake question asked about it and the operator answered" → `new-requirement` → parked
  (cli_records.py:46-49, 532-535). It never counts against the forecast, and the operator hears it as one more thing.
- Verdict: **counted (parked), not prevented**.

### Caught (for balance)
- C4 member omissions inside a declared population: **caught** — TM2 KR-01 (9th adapter) and KR-02 (json1 axis) were
  found by the two-method censuses and turned into frame-omission known rows that gate their build waves (M13).
- C3 premises below level: **caught** — row 4 refuses 17 TM2 premises today (M1); all 89 load-bearing premises carry a
  re-check command (M7).
- C8 dead critics read as clean (hole 189): **caught** — row 13 refuses any incomplete slot, missing lens or pin
  mismatch (gate_rows_b.py:284-309).
- Unknown fails: a missing row is a FAIL (gate.py:93-100); M1 shows the gate refusing a half-built program on 9 rows.

## 3. Does the method stop the AGENT from volunteering, and does that suppress critical findings?

- Volunteering in completeness turns: blocked only lexically (S4); blocked fully only when the classifier answers in
  time (S3), and only inside `cwd_roots` or an alias-named prompt (S1). In "other" turns and build panes the agent can
  volunteer freely.
- Suppression: the inverse of what one would want. The well-formed, located finding is blocked; the vague one passes.
  No safety route exists in triage, the rubric's clause (f) never reaches the triage rater, the §5.3 safety pause is
  unbuilt, and a third agent change request reddens the gate (S5). The design (REPORT §4.4, Appendix B break 1) treats
  every agent-originated late finding as noise to be routed away; for security and data-integrity that is the wrong
  default. Fix: a `hazard` route that bypasses the relay check and the CR cap, files to an immediate (not daily)
  safety queue, and pauses the closure, plus clause (f) verbatim in the triage brief.

## 4. Is the goal attainable, and what is the strongest attainable version?

- Unattainable part: "not to come back with … one more thing" for literally every item. Three causes are measured, not
  argued: holes every reviewer family misses (calibration u = 0.12, bracket 0.02–0.34); new operator intent (1.6 ideas
  per active session-day, REPORT §2.2 item 6); the world moving (4 of 200 unforeseeable; upstream release odds
  0.35–0.74 per program, §6.2). REPORT §2.4 and §7 make this case with receipts and I found nothing that refutes it.
- Strongest attainable version: (1) every item that could have been found from disk or a local probe is found before
  the claim; (2) every post-signoff change is predicted in count and class, traced to a store, and never generated by
  the agent re-judging on an ask; (3) the remaining stream is driven to a small number by front-end investment. The
  method's architecture targets exactly this. Its measured state is far from it on (3) (≈9.7 expected changes, S12),
  and the build misses (2) in the places S1, S3, S4, S7, S10 and S11 show.

## 5. Summary

| Scenario | Class / origin | Verdict |
|---|---|---|
| S1 build pane outside cwd_roots | C1; holes 1, 169 | slips |
| S2 sibling worktree research | C6; hole 139, TM2 replan | slips after the certificate |
| S3 classifier unavailable | method machinery | slips; certificate blocked by row 15 |
| S4 paraphrased new item | §2.2 cause 3 | slips |
| S5 late security finding | §3.11 (f) | delayed or buried |
| S6 mapped-not-covered axis | C4/C10; hole 96 | slips the gate |
| S7 prose-held known item | C1/C6; holes 61, 123, 169 | slips |
| S8 superlative with a digit | C11; holes 11, 56 | slips the lint |
| S9 untyped question frame | C1 | counted late |
| S10 "deployed and live?" | C1 | slips (render) |
| S11 understated forecast | estimator | counted, mis-forecast |
| S12 ≈10 expected changes | all | counted and forecast |
| S13 contact on a stand-in | C9; holes 153, 170 | partly slips |
| S14 confirm-by-click intake | C2u; holes 36, 107, 194 | counted as parked |
