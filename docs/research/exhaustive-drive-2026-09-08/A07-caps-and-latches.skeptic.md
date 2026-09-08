# A07 — SKEPTIC pass on "Caps, latches, exemptions and kill-switch false positives"

Wave: exhaustive-drive 2026-09-08. Read-only. Scratch under the session scratchpad
(`idl-all.jsonl`, `tx-30d.txt` 6,139 files / 7.82 GB, `tx-today.txt` 473 files, `scan.py`, `scan2.py`).
"Measured" = I ran it this pass. Every number below has its command.

## Answer first

The axis's **measurements reproduce** almost to the digit (IDL 11 days, 41 completion caps, 0 continuation
caps, 354/357 fires at count 1, 142 last-message kill sessions, 44 chains ≥8, chain histogram identical).
Two of its **conclusions are wrong**, and both change what should be built:

1. **The harness override IS on disk.** `{"type":"system","subtype":"informational","content":"A hook
   blocked the turn from ending …"}` occurs **6 times in 4 sessions** (9230f714, 5fde3a6f, 0ef2adfa ×3,
   06f84b8c), all on 2.1.220. The axis scanned user/assistant records and reported "0 hits / UI-only /
   unobservable". Lower bound on harness releases is 6, not 0.
2. **The harness counter resets on every tool-use round trip**, not only on a genuine user turn. Binary
   @164412526: `stopHookBlockingCount:0, transition:{reason:"next_turn"}` is the recursive call after tool
   results. Measured in the 311-chain transcript: every block is followed by `A:tool_use → U:tool_result →
   A:text → U:BLOCK`, so the count never exceeds 1. That is why 311-chains coexist with a cap of 8, and it
   refutes the open question "44 chains ≥8 may already be silently ending long drives" — a session that
   *works* between blocks never accumulates the count; only a text-only wedge does. The cap is the right
   shape already.

And one framing defect that lowers R1 and R3: the report counts **population at risk** and calls it harm.
Measured realized kill-switch effect in the 11-day IDL: `cleared kill-switch` on the armed path **0**;
`ship-floor-kill-switch` 6; completion-assert `kill-switch` 19. Only **8 of the 142** last-message-kill
sessions appear in the IDL at all. And R1's "100 writer sessions with every rail off" overlaps R2: for a
Bash-only writer the mechanical arm and ship floor are already off for the R2 reason, kill phrase or not.

## Re-checked numbers

| Claim | Report | Re-run | Command |
|---|---|---|---|
| IDL span / hook records | 11 d, 58,950 | 11 d (08-29→09-08), per-day counts identical except today (13,007 vs 11,753, later snapshot) | `cat idl.jsonl; gzcat idl.jsonl.*.gz` → `jq 'select(.hook!=null)\|.ts[0:10]' \| sort \| uniq -c` |
| `fired continue` count dist | 353@1, 3@2, 1@3 | **354@1, 2@2, 1@3** (357) | `jq 'select(.hook=="session-continue" and .disposition=="fired" and .reason=="continue")\|.count'` |
| `cap-reached` | 0 | **0** | `jq 'select(.reason=="cap-reached")' \| wc -l` |
| completion-assert `capped:3>=3` | 41 / 12 sids | **41 / 12 sids** (same per-sid counts) | `jq 'select(.hook=="completion-assert" and (.reason\|test("^capped")))\|[.ts[0:10],.sid[0:8]]' \| sort \| uniq -c` |
| anti-deference caps | 0 | **0** (1 latched) | same filter on anti-deference-nudge |
| `ship-floor-not-mine` | 90 | **92** (91 📦 · 1 🚀), 23 distinct sids | `jq 'select(.reason=="ship-floor-not-mine")\|.rung' \| sort \| uniq -c` |
| `mechanical-assignee` / `ship-floor-assignee` | 38 / 32 (1 rc 2) | **38 / 32 (31 rc 0, 1 rc 2)**; mechanical record carries no `confirm_rc` (verified sample) | `jq 'select(.reason=="ship-floor-assignee")\|.confirm_rc'` |
| genuine kill hits / isMeta suppressed | 179 / 442 of 13,147 | **181 / 446 of 13,182** | `scan.py tx-30d.txt` |
| `and stop` followed by a word | 88/175 (50.3%) | **153/187 (82%)** with a stricter terminal test (line-end after optional `.!;:)`) | `scan.py` |
| `just do not` matched | 3 | **7** (+16 `just do <other>`) | `scan.py` |
| first/last genuine msg carries kill | 154 / 140 | **156 / 142**; single-msg sessions 4,966; single-msg-kill **127** | `scan.py` |
| last-kill sessions that wrote | 100 | **75** with Edit/Write tool_use; **119** with Edit/Write or any Bash | `scan.py` |
| chain histogram / ≥8 / top | 44; 311,236,220,206,153 | **identical**: 44; 311,236,220,206,153,123,93,84,79,72 | `scan.py` |
| block records isMeta | 620/630 today | in all 39 chains ≥8: **meta=100%, nonmeta=0** | `scan2.py` |
| override message on disk | 0 / 7.27 GB | **58 lines in 29 files; 6 are `type:system` harness records** (rest: quoted prose in user/assistant/result records, incl. this wave's own) | `scan2.py` → `override-hits.tsv` |
| tool_use census 24 h | Bash 20,879 · Edit 289 · Write 79 | **Bash 21,496 · Edit 305** (473 files) | python over `tx-today.txt` |
| writer sessions bash-only | 229/260 (88.1%) | **170/214 (79%)** bash-only · 38 both · 6 edit-only · 259 neither (narrower idiom regex) | python over `tx-today.txt` |
| transcripts >25/69/150 MB | 29 / 7 / 2 of 6,131 | **29 / 7 / 2 of 6,139** | `xargs stat -f %z \| awk` |
| `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` in settings/zshrc | (not checked) | **absent** in all 5 config dirs and `~/.zshrc` → default 8 | grep |
| `ENABLE_STOP_REVIEW="0"` | dead knob | present in all 4 config dirs' `env` (binary count not re-run) | `jq .env settings.json` |

Not re-run: hook wall time on the 240 MB transcript (executing Stop hooks against live state is a write
risk under this wave's rules); accepted as axis-measured.

## Verdicts

### R1 — terminal-only kill switch + ignore a single-message session's brief. PARTIALLY REFUTED (55%)

*Holds:* the regex at `session-continue.sh:224` accepts any non-alnum after `stop` and `just do [^[:space:]]`
matches `just do not` (7 measured); `last_user_msg()` (:262-269) skips `isMeta==true`, and block records are
isMeta=true (100% in the 39 long chains), so a single-brief session's answer is constant for life.

*Refuted or overstated:*
- **Realized harm is ~25 events / 11 d, not 100 sessions.** `cleared kill-switch` on the armed path: 0.
  Only 8/142 last-kill sessions appear in the 11-day IDL. The "continuation actuator … switched off" clause
  has no measured instance.
- **Double count with R2.** Of the 142, 75 used Edit/Write; the other 67 were already invisible to the
  mechanical arm and ship floor for the R2 reason. Kill switch and oracle blindness are the same silence
  on those sessions; the report attributes it to both.
- **Hand-read disagrees on the class that matters.** My n=21 (every 9th of 181): 11 (52%) not stop
  orders, **8 (38%) conditional scoped stops in briefs** ("if blocked, say so and stop", "return UNKNOWN
  and stop", "STAGE it and stop"), 2 (10%) genuine. The report's 80% folds the conditional class into
  "not stop orders". A brief-blind kill switch forces continuation on exactly those — a nag on a
  legitimate stop, bounded to ≤ CC_MECH_MAX + CC_SHIP_FLOOR_MAX = 4 blocks, but it is the wave's named
  anti-pattern.
- **The headline example is not reached by the fix.** The max-autonomy brief (21fe99e4) is genuine
  message **#7** of its session; 156/181 hits are at index 1, the rest are not. Only the regex half touches it.
- **Reverses a recorded decision without citing it.** `session-continue.sh:257-260`: "all 9 that are not
  [isMeta] are fire/recycle briefs — genuine instructions TO this session, which SHOULD disarm."
- House rule: a tighter regex is still a denylist of spellings (`denylist-enumerates-spellings-not-the-class`).
  Existing fixture `tests/session-continue.bats:121` pins "just do the one fix" as a kill phrase — the
  `just do( not|n't)` exclusion keeps it green; the terminal-only change must keep "just do X and stop" green.

*Fail direction of R1 as written:* errs toward blocking stops that briefs explicitly licensed. Split it: the
regex half (terminal `and stop`, exclude `just do not`) is S and sound (~80%); the brief-exclusion half is
~35% until the conditional-stop class is measured against real idles.

### R2 — teach session-writes.sh to see Bash writes; return rc 2 when a path cannot resolve. FINDING HOLDS, FIX HALF-REFUTED (60%)

*Holds:* `session-writes.sh:143` selector confirmed; `session_unlanded_mine` (:342) and `session_dirty_mine`
(:244) both consume `session_writes_paths`, so a Bash-only writer yields rc 1 → `ship-floor-not-mine` and no
mechanical arm. Decomposing the 92 events' 23 sids: **19 had zero Edit/Write tool_use; 16 of those had Bash
write idioms** (`sed -i|tee |cat >|>>|<<|git checkout/stash/commit|cp|mv`); 3 sids had Edit/Write (correct
sibling exoneration); 3 were read-only (correct abstain). So ~70% of the "largest exemption" is the oracle
gap, not 100%.

*Refuted:*
- **The rc-2 half is a no-op.** Mechanical arm: `[ "$mrc" -eq 0 ] || return 1` (:890). Ship floor: any
  rc≠0 abstains (:1018, :1022). completion-assert's `_ca_mine` already downgrades rc 1 to rc 2 (header
  :14-16). operator-readout's certificate needs rc 0. Relabelling 170 sessions from rc 1 to rc 2 changes
  zero decisions.
- **The path-extraction half is the class the file's own header rejects** (:40-44: "parsing shell to find
  writes is the prescribed-remedy-worse-than-the-bug class"), and a write-idiom regex is a denylist of
  spellings. Its false-conviction surface is understated: `git checkout -- <path>` reverts a sibling's dirt
  and would attribute that path; `tee -a` into a file another session owns likewise. The `git status`
  intersection removes non-repo paths, not repo paths the session touched without authoring.

*Fail direction:* as specified, errs toward a `#105`-class false conviction that the innocent session
cannot clear. Do only the extraction half, with the tightest idiom set (`sed -i`, `>`/`>>` to a path, heredoc
to a path, `tee` without `-a`), one bats mutant per idiom, and leave rc semantics alone. Backlog `ed54373d639b`.

### R3 — re-key completion-assert / anti-deference caps on (sid, HEAD). REFUTED AS EVIDENCED (35%)

- **"29 of 41 suppressed a later close" is tautological.** The cap check (:1075-1080) runs after tell
  detection; every `capped` record is a post-cap close with a tell. It is 41, and none was shown to be a
  false done.
- **Wrong denominator.** The cap counts **fires per class** per (CFG, SID, CWD) (:1035, :1073), not
  evaluations. "72 sessions ≥4 evaluations" is irrelevant; exposure is **12/301 sessions (4%)** that fired 3
  times, all `ledger false-done` at 🔧/📦/⛔ (measured per-sid).
- **The only hand-read exonerates the cap.** The report's read of `41aaaa07` says its post-cap closes were
  high quality — the axis's own evidence that the suppressed checks were not needed.
- **HEAD re-keying does nothing for the dominant arm.** 63 of 112 ledger fires are 🔧 (dirty, uncommitted):
  HEAD does not change while a session keeps closing over dirt, so the re-key never re-arms there; it re-arms
  only on 📦 sessions that commit and re-close — and "a new HEAD means the facts changed" is true precisely
  where the fires were probably right.
- **Anti-deference hit its cap 0 times in 11 d**; re-keying it has no trigger.

*Fail direction:* more fires with no measured false-done in the suppressed set — `alarm-polarity`. Cheaper
first step: R4's instrumentation half (record arm/rung/facts on the capped record), then decide.

### R4 — make a spent cap loud + file a cc-backlog row. PARTIALLY REFUTED (55%; instrumentation-only variant 90%)

*Holds:* `session-continue.sh:1125` emits `{systemMessage}`; `docs/research/final-response-shaping-2026-08-08.md:27,55`
confirms it is human/TUI-only. `completion-assert.sh:1079` and `anti-deference-nudge.sh:350` log `capped:N>=M`
with no arm/rung/facts (verified).

*Refuted:* (a) session-continue's cap path fired **0 times in 11 d** — fixing its message addresses no
measured event; (b) a Stop hook minting backlog rows on 41 trips / 11 d is the `parking-state-cheap-entrance-no-exit`
lesson with the exit ("auto-close on next clean close") unbuilt; it is also a write side effect from a Stop
hook. Keep the IDL field; drop the row.

### R5 — log `confirm_rc` on `mechanical-assignee`. HOLDS (95%)

`:846` logs bare; `:974` logs `{assignee,confirm_rc}`; 38 bare events, sibling shows 1/32 rc 2. Pure
instrumentation. Copy the `jq -cn --arg a --argjson c` shape.

### R6 — correct CLAUDE.md's "CLAUDE_CONTINUE_MAX bounds runaway". HOLDS (88%)

`~/.claude/CLAUDE.md:888` carries the sentence; `session-continue.sh:117` deletes `.count` on every `set`;
`:1149` instructs the re-arm; 0 `cap-reached` / 11 d; 354/357 fires at count 1; 311-chain measured. Add the
corrected harness fact: the harness cap resets on every tool-use turn, so neither cap bounds a working grind
— only a text-only wedge (harness, 9th block) or the mechanical arm (`CC_MECH_MAX × CLAUDE_CONTINUE_MAX`).

### R7 — do not narrow exemptions. HOLDS (80%)

`agent-identity.sh:46-63` ancestry walk with cross-field consistency confirmed; team-assignee ≈80 per hook
across dispatch-assert / operator-readout / boundary-handoff (+5 anti-deference) confirmed; completion-assert
0 team-assignee. Correction: `ship-floor-not-mine` is ~70% oracle gap, ~15% correct sibling exoneration,
~15% read-only sessions idling in a 📦 checkout — not "the leak" in full.

## What the axis missed

1. Harness override records exist (`type:system`, `subtype:informational`): 6 / 4 sessions / 2.1.220.
2. Harness counter resets on `next_turn` (tool use), binary @164412526; measured block→tool_use→text→block
   pattern in the 311-chain; the cap only catches a text-only wedge. Open question 5 is answered: no.
3. Realized vs at-risk for the kill switch (0 armed-path clears; 25 abstains; 8/142 sessions in IDL).
4. R1/R2 double count the same writer sessions.
5. Kill-hit position: 156/181 at index 1; the headline brief is index 7.
6. The recorded decision at `session-continue.sh:257-260` that briefs SHOULD disarm.
7. Decomposition of the 92 `ship-floor-not-mine` events by cause (16 oracle / 3 exonerated / 3 read-only / 1 missing).
8. completion-assert cap = fires per class per (CFG,SID,CWD); cwd hop resets it; no capped close shown false.
9. Version mix: 30 of 39 chains ≥8 ran on 2.1.220, 9 on 2.1.260 — the binary read is 2.1.260 only.
