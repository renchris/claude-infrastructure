# Lens (completeness critic): end-to-end live behavior of method v1.1's back half and re-ask path

Auditor session 2026-10-04, worktree `wt-cc-024434-55635`. Every number is labeled **measured** (a command I ran
this session), **modeled** (a simulation), or **asserted** (a doc's claim I did not re-run). No operator prompt or
transcript reply is quoted here: this repo keeps only aggregates of private evidence
(`docs/research/research-calibration/evidence/PRIVATE_MANIFEST.json` "why"), so transcript evidence is given as
counts and session-id prefixes only.

## 0. What I could and could not run, and why

Two instructions conflicted. The computed task asked for real vendor-diverse rounds (round.sh/courier.sh), seeds,
and 30+ headless `claude -p` sessions. The hard rules for this audit forbid running round.sh, courier.sh, vendor
CLIs, record-writing kit verbs, and anything that spends vendor quota. I followed the hard rules. So:

| Task step | Done as specified? | What I did instead |
|---|---|---|
| (1) fixture with known truth | yes | `limit-recover-100p` (102-line plan at `bb44e2193`), 22 known later holes in the private history record |
| (2) back half: freeze, rounds, seeds, gate | **partly**. Freeze, rounds, seeds not run (they write records or spend quota) | `gate.sh run` / `render` / `requires` in a sandbox (all write-free on a FAIL, `lib/gate.py:139-153`); certified state and certificate **hand-placed** and labeled so |
| (3) 30+ headless sessions | **no** (quota rule) | the three hooks invoked directly with the harness payload shape, a stub classifier per label, plus a replay of the relay check over 64 real operator asks paired with the real replies they got |
| (4) honesty against truth | yes, against the calibration replay's recorded forecast and the history record | |

So the empirical rate of each router label on live operator phrasings is **not measured by me**. The only reading of
it is the build plan's (asserted, `docs/plans/RESEARCH_PROGRAM_BUILD.md:171-177`): fallback 0.96 at load ~295 and
0.51 at load 45-80 against the 6 s limit. My load readings this session: `uptime` => 35.47, 37.86, 27.07, 36.26
(1-min averages, 10-core box), i.e. inside the 45-80 band's lower edge or just under it.

Safety receipts (measured): sandbox `F=/tmp/lens-e2e.Ep1NfW`, `CC_RESEARCH_HOME=$F/home`,
`CC_RESEARCH_REGISTRY=$F/home/programs.json`, `COMPLETION_STATE_DIR=$F/castate`, `COMPLETION_IDL=$F/idl.jsonl`.
`stat -f %m ~/.claude/autonomy/research/programs.json` => `1790910680` before and after every step;
`ls ~/.claude/autonomy/research/` => `programs.json router-heldout truememory-2-0` (no `route-state/` created live).
No pane or session was sent input.

## 1. Fixture

- Plan: `git -C ~/Development/claude-infrastructure show bb44e2193:docs/plans/LIMIT_RECOVER_100P.md` => 102 lines,
  copied to `$F/fixture/`.
- Known truth (private, read-only):
  `~/Development/claude-private/docs/research/research-calibration-2026-10-01/history/limit-recover-100p.json`:
  `holes_total 22, holes_at_freeze 18, fix_born 4`; found_by `probe_contact 14, desk_review 5, build 2, operator 1`;
  omissions 11. Surfaced 2026-09-08 .. 2026-09-29 (H1 operator, 09-29; H2/H3/H11-H17 probe contact, 09-19).
- Calibration replay row for this plan (`docs/research/research-calibration.jsonl`, measured by the calibration run,
  one Lite round, 6 reads): `known_detected 8` of 18, `known_missed_desk 2`, `known_missed_nondesk 8`,
  `forecast_point 2.57`, `forecast_95 18.13`, `realized_missed 10`, `point_exceeded False` (desk-only),
  `point_exceeded_total True`.
- Sandbox registry: one program `lr100p-fixture`, alias `LR100P fixture`, `cwd_roots [$F/fixture]`.

## 2. Stage-by-stage execution log

| Step | Command | Result | Label |
|---|---|---|---|
| gate at `registered`, empty records | `gate.sh run --program lr100p-fixture` | rc 1. FAIL rows 1, 6, 7, 8, 9, 13, 14, 15 (`router not built (wave B1): CC_RESEARCH_ROUTER is unset`), 16. **PASS on rows 2, 3, 4 ("no premises recorded"), 5, 10, 11, 12 ("0 item(s) reconciled") with zero records** | measured |
| render | `gate.sh --render` | `Research: lr100p-fixture — registered; not certified. Certification rounds counted: 0` rc 0 | measured |
| build-wave gate | `gate.sh requires --wave W1` | `REFUSED … registry state is 'registered' … no certificate` rc 1 | measured |
| freeze / rounds / seeds | not run | forbidden by the audit's hard rules | — |
| row 15 live reading | not re-run (69 haiku calls) | asserted FAIL, plan :171-177; row 15 is a hard FAIL with no FILED path (`lib/gate_rows_b.py:344-353`), so `gate.sh run` cannot write a certificate on this machine (`lib/gate.py:146-150`) | asserted + code |
| hand-placed certified | registry state edited in the sandbox; `CERT-v1.json` hand-written (fingerprint model `HAND-PLACED`) | render prints 7 lines incl. `Signed frame: 100.00% closed.` and `· take-backs 0` | measured |
| live program check | `ls ~/.claude/autonomy/research/truememory-2-0/rounds/` | only `fc1 fc2 census census-grids`: no certification round has ever run live; no `route-state/` dir exists, so the router has never routed a real prompt | measured |

The vacuous PASS rows are bounded by row 1 (every checklist row mapped) and row 9; I rate them minor.

## 3. Positive control (hook level, not a headless session)

Payloads of the UserPromptSubmit / PreToolUse shape piped into `hooks/research-precognition-nudge.sh` and
`hooks/research-block.sh` from this worktree (byte-identical to the live checkout: `cmp` => `same` for all six
files), stub classifier `CC_RESEARCH_CLASSIFIER='echo completeness'`:

| cwd | nudge output | Bash `cat` | Bash `gate.sh --render …` | Agent | Read |
|---|---|---|---|---|---|
| `$F/fixture` | relay context injected | DENY | allow | DENY | DENY |
| `$F/outside` | nothing | allow | allow | allow | allow |

Registration (measured): `~/.claude/settings.json` PreToolUse `matcher "*"` → `research-block.sh` timeout 5
(:861-868); UserPromptSubmit `research-precognition-nudge.sh` timeout 10 (:976-977); `.claude-next`,
`-secondary`, `-tertiary`, `-quaternary` settings are symlinks to it. Block-hook latency at load 27:
p50 0.104 s, p90 0.144 s, max 0.151 s over 20 calls (measured), far inside its 5 s timeout.

## 4. Route label × tool matrix (deterministic; stub classifier forces each label)

Prompt "Are you sure?" in `$F/fixture`; then each tool call; then the relay check on the reply
`Yes, complete. One more thing: \`lr-reset-poller\` at scripts/limit-recover/lr-reset-poller.sh:468 …`.

| Route label (how produced) | Bash cat | Read | Grep | WebSearch | WebFetch | Skill | SendMessage | Agent | Bash codex | Relay check |
|---|---|---|---|---|---|---|---|---|---|---|
| completeness | DENY | DENY | DENY | DENY | DENY | DENY | DENY | DENY | DENY | **BLOCK** |
| pushback | DENY | DENY | DENY | DENY | DENY | DENY | DENY | DENY | DENY | **BLOCK** |
| concern | allow | allow | allow | allow | allow | allow | allow | DENY | DENY | off |
| new-idea | allow ×9 | | | | | | | allow | allow | off |
| research-order | allow | allow | allow | allow | allow | allow | allow | DENY | DENY | off |
| work-order | allow ×9 | | | | | | | allow | allow | off |
| other | allow | allow | allow | allow | allow | allow | allow | DENY | DENY | off |
| **unavailable** (stub sleeps past `CC_RESEARCH_CLASSIFIER_TIMEOUT=1`) | allow | allow | allow | allow | allow | allow | allow | DENY | DENY | **off** |
| **unavailable** (stub exits 1) | same | | | | | | | | | **off** |
| **unavailable** (stub prints two labels) | same | | | | | | | | | **off** |

All measured. REPORT §4.1 table last row and §4.2 say a timeout, error or mixed label "is treated as a completeness
question … Certificate read only"; the code (`router.py:296-302, 358-360, 563-566, 638-641`) treats it as
`unavailable`: research verbs only, own tools allowed, no Stop check. At the asserted 0.51 fallback, about half of
live completeness asks would take the `unavailable` row.

Research-verb deny spellings (label `other`, measured): DENY for `codex exec`, `$(command -v codex)`,
`/opt/homebrew/bin/claude --print`, `… | claude -p`, `xargs … codex`, `~/.local/bin/agy`, `round.sh`,
`bash -c 'gemini …'`, `cc-research reopen`. **allow** for `python3 -c "subprocess.run(['codex',…])"`,
`perl -e 'system("codex …")'`, `eval 'codex …'`, `npx -y @openai/codex exec`, `claude-latest -p …`
(`which claude-latest` => `~/.claude/bin/claude-latest`, the operator's default launcher), `claude2 -p …` (a zsh
function visible to the Bash tool), `c=codex; $c exec`, and peer relays `kitty @ send-text`, `osascript`,
`cc-mailbox send`. The deny is a spelling list (`router.py:382-386, 476-491`).

## 5. Relay check (Stop, ARM R) against real and synthetic replies

**5a. Real replies.** The router's tuning set (`~/.claude/autonomy/research/router-heldout/tuning.jsonl`, 96 rows;
the sealed set was not touched) carries `source = <sid8>@<timestamp>`. I paired each row with the last main-agent
text reply of that turn in its transcript: 92 paired (2 pushback rows had no file). Running
`router.relay_violations(reply, <§4.3 example certificate>, label)` over the 64 completeness-strata replies
(measured): **52 of 64 would be blocked (81%; Wilson 95% CI 70-89%)**. Reasons (a reply can carry several): names
tokens 45, more than 3 extra lines 42, stock item phrase 11, opens "no" without an event word 10. Median reply length
9.5 lines. The dominant trigger is the resident close format itself: the session-close protocol requires
`Good to close: …; follow-on: <filed ids>` and backticked ids/commands on line 2-3
(`~/.claude/rules/10-session-close.md` § Origin close contract), which ARM R's `follow-on: (?!none)` ITEM pattern and
TOKENS regexes (`router.py:580-600`) reject. Inside a program the model is therefore instructed one way by the
injection and trained the other way by every resident close rule, and only the latch below arbitrates.

**5b. Compliant synthetics** (measured): 6 of 7 relay-shaped replies (verbatim, fenced, with "Yes." prefix, with 1-3
neutral explaining lines) pass; the 7th failed only for naming `gate.sh --render` in backticks. So a disciplined relay
is satisfiable: the check has a low false-block rate on compliant text.

**5c. Truth-blindness** (measured, against the hand-placed certificate, label completeness):

| Reply | About a real fixture hole? | Relay check |
|---|---|---|
| A verbatim certificate | – | pass |
| B certificate + "One triaged escape has landed since signoff." | yes (count only) | pass |
| C "No: a triaged escape" + certificate + escape with `LIMIT_RECOVER_100P.md:49` (H1) | **yes, real** | **BLOCK** (file:line, path) |
| D "No — a triaged escape …: the plan has no acceptance row, … 1 of 5" (H2) in prose | **yes, real** | pass |
| E "Yes" + certificate + "The n=5 production run is not yet run." (H2) | **yes, real** | **BLOCK** (stock phrase "not yet run") |
| F "Yes" + certificate + "The transplant runs before the capacity re-gate, so a refusal leaves a husk." (H3) | **yes, real, new item after a yes** | **pass** |

So the check blocks real holes when they carry a location or a stock phrase and passes them in plain prose: it
is a lexical filter whose verdict is uncorrelated with whether the named item is real.

**5d. Lifetime cap** (measured, `completion-assert.sh` in the sandbox with a synthetic transcript, 4 successive
completeness asks in one session each answered with a new item + file:line): ask 1 BLOCK, ask 2 BLOCK, **ask 3
pass, ask 4 pass**; IDL `abstained … capped:relay:2>=2`. The latch file is keyed `CFG|SID|CWD`
(`completion-assert.sh:289-301`) and GC'd only after 7 days (:1305), so the cap is 2 blocks per session lifetime,
not per ask.

**5e. Kill-switch interaction** (measured): 0 of 66 completeness-strata operator prompts contain a phrase matching
`CA_KILL_RE` (`completion-assert.sh:182`), which would make the hook abstain before ARM R. Not a live risk.

## 6. The certificate cannot carry what happens after signoff

Measured: I added three hand-placed triaged escapes (H2, H3, H6) to the sandbox records (`challenges.jsonl` with
`triage: escape`, `changes.jsonl` with `cause: escape`) and re-rendered: `diff render-before render-after` =>
**identical**. `lines_for` (`lib/gate_cert.py:190-230`) renders the issue-time JSON with the literal
`· take-backs 0` (:213) and only the forecast on the "After signoff" line; `cc-research verdict`
(`lib/cli_core.py:233-277`) adds pending concerns and the menu, never a realized count; `grep -rn 'take-backs'`
over `scripts tests hooks bin` hits only that literal. REPORT §4.3's "After signoff: 1 material change (forecast
about 3 …)" is therefore not built. Combined with §5c and §5d: after signoff, a confirmed escape is absent from
the relayed lines, a reply that names it with a location is blocked twice per session, and the certificate keeps
asserting `take-backs 0`.

## 7. Honesty against the fixture's truth

| Question | Answer | Label |
|---|---|---|
| Could any re-ask reply surface one of H1-H22? | By construction only in the cases ARM R passes (prose, after 2 blocks, or on any non-relay label); a compliant relay surfaces none, and the certificate renders none (§6) | measured |
| Did the relay check block a reply naming a real one? | yes for C (H1, with file:line) and E (H2, stock phrase); no for D (H2 prose) and F (H3 prose) | measured |
| Is there any agent channel for a real hole? | yes, outside a relay turn: `cc-research concern add --raised-by agent` (`lib/cli_records.py:29, 354-366`), which REPORT §4.4 says is inadmissible; inside a relay turn every tool but the certificate read is denied | code |
| Did the forecast cover the realized count? | point 2.57 vs 10 realized (total) — exceeded 3.9×; vs 2 realized desk-only — held. 95% bound 18.13 — held, but it equals the audited hole count at freeze (16.1) plus margin, i.e. "every hole could be missed" | measured from records |
| Across all 16 replayed plans | realized total > point forecast in 14/16; the 95% bound ≥ the plan's whole audited hole count at freeze in 14/16; median bound 44 vs median realized 12; three bounds above 460 | measured from `research-calibration.jsonl` |

The REPORT's "point forecast exceeded on 6 of 16" (§3.12 reading 3) compares desk-detectable holes only; what the
operator experiences as "one more thing" is every later hole, where the point forecast was exceeded 14 of 16 times.
The replay is one Lite round, not a full certification, so these are upper-side readings for a certified program.

Also: the certificate forecast runs on pre-calibration inputs (`estimate.py:36-43` `BASE u=0.05, fpp=0.01`, used at
`:329, 338`); I re-ran `estimate.py simulate --profile lite --n0 20 --reps 2000` => `desk_left 2.67,
invisible_left 1.07, p_any 0.96, cap_pct 46.5` (modeled), against the calibration's measured-input reading of 6.7
desk and 3.0 invisible with 98% at the cap (asserted, REPORT §3.12). Already reported by lens-adversarial (M9) and
lens-goal-fit; confirmed.

## 8. The relay test (gate row 14) measures a different path from the live one

Code-read, `scripts/research-kit/workflows/rehearsal.workflow.js` and `lib/cli_cert.py:369-475`:
- Trials are Workflow `agent()` calls (:55-61). A subagent prompt does not pass through UserPromptSubmit, so the
  router never classifies a trial and no relay context is injected; the live path in §4 is never exercised.
- The "outside the program root" trial's `cwd` is a string the script writes into the result (:58-61); the agent's
  process cwd is not moved (the file's own header admits it, :11-14). `relay_fails` accepts that string (:411-417).
- The tool list judged is the agent's own report (`REPLY` schema, :34-35; "return … every shell command you ran").
- Four phrasings only (:26-27), none of them the operator's dominant "100.00/100.00 complete" form; a trial with no
  label defaults to completeness (:391-395) even for "if more research moves your conviction, do it now", which
  the live router would label research-order (no relay, no Stop check).
- Row 14 passes on "relay unstable" (`lib/gate_rows_b.py:330-332` returns `verdict(…, fails, [], ["relay unstable"])`),
  so the relay behavior never blocks a certificate. The only blocking gate on re-ask behavior is row 15 (router
  recall), and §4 shows recall alone does not determine what the operator sees.

## 9. Routing from another pane

Sandbox registry with the live program's aliases (`TrueMemory 2.0`, `tm2`), `rp_resolve_prompt` (measured):
routed `is tm2 done?`, `Is TrueMemory 2.0 complete?`, `Is truememory-2-0 done?`; **unrouted**
`… complete on docs/plans/TRUEMEMORY_2_0.md?`, `is truememory complete?`, `is the tm2-plan done?` (the boundary class
`[!a-z0-9_-]` treats `-` as a word character, `research-program.sh:160-163`), `… with the TrueMemory plan?`.
An unrouted pane gets the standing rules in full, including the close-question rule that drives "one more thing".
4 of the 66 historical completeness asks cite a plan path (measured), so most asks would be routed by cwd if asked
from the program's own pane.

## 10. Where observed behavior contradicts earlier desk conclusions

| Earlier conclusion | Observation here |
|---|---|
| REPORT §4.1/§4.2: a classifier timeout/error/mixed label is treated as completeness, certificate read only | Measured: all three produce `unavailable`; Read/Grep/WebSearch/WebFetch/Skill/SendMessage allowed; relay check off (§4) |
| REPORT §4.2 "What this guarantees: a re-ask can start research only if the classifier positively mislabels it" | Measured: under `unavailable`, `other`, `concern`, `research-order`, research by spelling variants (`claude-latest -p`, `claude2 -p`, `npx … codex`, python/perl subprocess) and by peer relay is allowed (§4) |
| REPORT §4.3/§4.4: the answer changes on a triaged escape; after-signoff count is printed | Measured: render identical after 3 triaged escapes; `take-backs 0` is a literal (§6). Confirms lens-as-built F3 empirically |
| REPORT §4.4: the Stop check blocks any reply naming an item the certificate lacks | Measured: blocks 2 per session then abstains; passes prose items (§5c, §5d). Confirms lens-adversarial M3/latch by execution |
| REPORT §3.8 rehearsal: a session with full resident instructions, one trial from a pane outside the directory | Code: Workflow subagents, router bypassed, cwd a label, tools self-reported; row 14 passes on "relay unstable" (§8). Not raised by earlier lenses beyond the phrase list (compare-blind-designs) |
| REPORT §4.4 ("an agent cannot file a concern") | Code: `--raised-by agent` is accepted outside relay turns (§7) |
| REPORT §3.12 reading 3: "the printed 95% bound still holds" as reassurance | Measured from records: it holds by width — at or above the whole hole count at freeze in 14/16 plans (§7) |
| REPORT open item 15 estimated the "yes + new item" rate at ~2-3 of 16 regex hits | Measured: 11 of 64 real replies to completeness asks carry a stock item phrase (17%); 52 of 64 (81%) would be blocked by ARM R, mostly for the resident close format (§5a) |
| Earlier lenses (code-read) assumed the fallback path is the main live risk | Agreed and sharpened: even the `completeness` path is only as strong as a 2-block lexical latch |

## 11. Verdict

As built, the back half cannot run to a certificate on this machine (row 15 hard FAIL, asserted; no live
certification round has ever run, measured), and the re-ask path that would follow it stops "one more thing"
mainly by muting rather than by completeness, and not reliably: the strongest layer (all-tool deny + relay check)
engages only on a positive `completeness`/`pushback` label, the fallback that the measured classifier latency makes
common turns both off, the relay check passes plain-prose additions and lapses after 2 blocks per session, and the
relayed certificate cannot show a single post-signoff escape while asserting `take-backs 0`. When the layers do
engage, they suppress real holes as readily as false ones (§5c). The operator's goal as stated (zero
post-signoff change) is physically unattainable at any spend by the method's own measured numbers
(P(any material change after signoff) 0.63-1.00 across REPORT §3.12's table, and 0.93 / 0.96 in my own
`estimate.py simulate --profile lite --n0 16|20` runs, modeled); the strongest attainable version is an
honest, live-updating forecast-versus-realized counter that the re-ask answer must carry, which is exactly the part
not built.

Conviction that the method as built is the best attainable for the goal on this lens: **12%**.
