# C1 judge, implementability and regression lens

Round 2, 2026-10-18. Judges `round2/C1-last-assistant-message.md` (the design) against the brief's six
constraints, from one angle: can it land as written without breaking anything? I stayed read-only in the
repo. Every run used copies under `/tmp/r2-C1-judge/` (`git archive` of HEAD `72a18b575` and of `main`
`d4e3a1113`), with every state seam pointed at a fresh `/tmp/r2-C1-judge/runs/r.*`. Each number below says
whether it was measured (with the command) or estimated (with the method).

**Verdict: clears 90, at 91%.** The patch is small and mechanically correct, and I reproduced every result I
re-ran, independently of the designer. It has four implementation gaps, all cheap to close before landing
(§4). None of them is a behavioural regression in the two hooks it changes.

## 1. Insertion points and applicability

| Check | Result (measured) |
|---|---|
| `hooks/completion-assert.sh:279-286` holds the extractor plus `abstain "no-assistant-text"` | yes (`sed -n 276,290p`). Hunk header `@@ -276,13` matches. |
| `hooks/anti-deference-nudge.sh:155-163` holds the same | yes (`sed -n 140,170p`). Hunk header `@@ -152,14` matches. |
| `$input` holds the raw payload, assigned once | `completion-assert.sh:136` and `anti-deference-nudge.sh:62`. `grep -n 'input='` finds no other assignment. |
| `LASTJSON` is used after the block | no (`grep -n LASTJSON`). It is local to the extractor, so leaving it unset on the payload path is safe under `set -u`. |
| The hooks changed between the designer's base `f12dd4b12` and HEAD | no (`git diff --stat f12dd4b12 HEAD -- hooks tests lib scripts` is empty). |
| The hooks differ between HEAD and `main` | no (`git diff HEAD main -- <both hooks>` is empty). `main` is 30 files ahead, and none of them is these two. |
| `git apply --check /tmp/r2-C1/C1-full.diff` | applies to both the HEAD archive and the `main` archive. |
| The applied files equal the designer's tested copies | `cmp` finds all 3 files identical to `/tmp/r2-C1/patched/`. |
| Every other line the report cites | 13 of 13 spot-checked are at the cited line: `:355`, `:375`, `:397`, `:441-442`, `:1557`, ad `:168`, ad `:594`, `handoff-claim-assert.sh:53`, `dispatch-assert.sh:157`, `operator-readout.sh:1898`, `subagent-stop.sh:93`, `stop-failure-marker.sh:111`. |
| None of the 6 files owned by the other session is touched | yes (the diff touches 2 hooks and 1 new suite). |
| Live wiring | `jq` over the 4 live `settings.json` files: both hooks are `Stop`-only, `timeout 5`, and invoked directly as `~/.claude/hooks/<hook>.sh`. No wrapper rebuilds stdin, so the key reaches the hook. Both files are symlinks into `~/Development/claude-infrastructure/hooks/` (`ls -la`), so the change goes live on fast-forward with no install step. |

## 2. Interpreter, lint, runtime cost

- **bash 3.2.** `/bin/bash -n` parses both patched hooks (GNU bash 3.2.57, measured). At runtime under
  `/bin/bash` (my runner `/tmp/r2-C1-judge/edge.sh`), the outcomes match bash 5 for:
  - no key: `no-close-tell`, `no-tell`;
  - key carrying a close: `fired`;
  - key only nested under another field: falls back to the transcript and `fired`;
  - truncated JSON: the existing `no-transcript-path` abstain;
  - a 295 KB final.

  Every run exits rc 0 with 0 bytes of stderr. The rs13 replay under `/bin/bash` also fires both hooks, as
  under bash 5. The `case` sits at top level, so the lesson that bash 3.2 rejects `case` inside `$( )` does
  not apply. The existing `completion-assert-forks.bats` and `completion-assert-durations.bats` already run
  the hook under `/bin/bash`, but only on the no-key path.
- **Lint.** Bare `shellcheck` reports 0 findings on both patched hooks (rc 0, measured).
- **Cost of the `case` probe.** 20 probes over a 295 KB payload cost 0.04-0.18 s user time in total. That is
  at most about 9 ms per probe, the worst case being bash 3.2 in a UTF-8 locale with the key absent
  (`/usr/bin/time -p … casebench.sh`). Real payloads are a few KB, so the probe is negligible.
- **Process count.** Forks suite test 1, which I ran myself, prints `20 external calls before, 15 after` on
  the no-key path (the budget is 16). The key path drops the scan's `jq` and `tail` and adds one `jq` on
  `$input`, a net saving. It stays pure jq, as README F10 requires: no `python3`.
- **Large-message slowness is not C1's.** anti-deference on a 295 KB final ran 19.7 s unpatched (read from
  the transcript) against 16.4 s patched (read from the payload), at load average about 500. That cost
  scales with message size whatever the source, so it is a pre-existing timeout exposure, not a regression.

## 3. Tests: what pins the changed behaviour

- **Nothing pins the extractor's text.** `grep -rn 'LASTJSON\|Extract the LAST\|isSidechain != true' tests/`
  finds only test names. The tests that read the hook source with `grep` or `sed` target other regions:
  - `completion-assert.bats:842` reads `CA_PLACEHOLDER`;
  - `operator-surface-scope.bats:268` counts `agent_is_assignee`;
  - `research-kit-built-states.bats:268,628` reads `_ca_rp_lib`.
- **No existing fixture sends the key to these hooks.** `grep -rln last_assistant_message tests/` finds only
  the stop-failure, subagent-stop, cc-limited, install-core and lr suites, and none of them runs either hook.
  So every existing suite takes the fallback, which the diff leaves unchanged except for indentation.
- **My independent bats runs** (from the sandbox copies; each passed `cc-bats` on its first attempt, through
  `/tmp/r2-C1-judge/retry-bats.sh`; plan line asserted):

  | Suite | Copy | Plan | ok | not ok |
  |---|---|---|---|---|
  | `stop-last-assistant-message.bats` (new) | patched | 1..6 | 6 | 0 |
  | `stop-last-assistant-message.bats` (new) | HEAD hooks (the RED check) | 1..6 | 3 | 3 (tests 1, 2, 5) |
  | `anti-deference-nudge.bats` | patched | 1..61 | 61 | 0 |
  | `completion-assert-forks.bats` (SHF_BASE through a read-only alternates borrow) | patched | 1..8 | 8 | 0 |
  | `completion-assert.bats` | patched | 1..185 | 185 | 0 |

  The designer's saved TAP for the remaining suites agrees with the report: durations 8/8, assignee 9/9, jev
  9/9 all skipped, and the siblings (`/tmp/r2-C1/bats/patched/*.tap`, `siblings/*.tap`).
- **Replay of the three race cases**, my runner plus a fresh landed fixture, with the designer's views. I
  checked the views are sound: `pre` is a byte prefix of `post`, and `lam.txt` equals `post`'s final text
  record.
  - HEAD with no key reproduces the live verdicts on 6 of 6 (`no-close-tell` and `no-tell`).
  - Patched with no key is identical, 6 of 6.
  - Patched with the key changes 4 of 6: rs13 fires both hooks (`fired false-done` and `fired deference`),
    and rs05 and rs01 fire completion-assert. This matches report §2.1 and §4.
- **The binary**, by my own `mmap` search of `claude.exe` 2.1.293:
  - `hook_event_name:"Stop",stop_hook_active:s,last_assistant_message:_e` at 195,022,749;
  - `FLUSH_INTERVAL_MS=100` at 196,608,143;
  - `ry` = `findLast(type==="assistant")` at 196,421,899.

  The surrounding text confirms `_e=he?ho(he.message.content,"\n").trim()||void 0`.
- **A precedent the report missed.** `core/hooks/completion-gate.sh:19`, the slim installer's own Stop hook,
  already reads `last_assistant_message`.
- **Gate selection.** The new suite names `$REPO/hooks/completion-assert.sh` and
  `$REPO/hooks/anti-deference-nudge.sh` literally in its executable text. By my reading of
  `scripts/gate-select.sh` (I did not run it), the literal-path clause will select it on future edits to
  either hook.

## 4. Concerns: none breaks the two hooks, but four should change before landing

1. **One matcher per concept: the read is copied, and there is no drift guard.**
   - The same 4-line payload read is pasted into both hooks. Its only link is a prose pointer in
     anti-deference to completion-assert. Constraint 6 and close-shape.sh's header warn that copies of a
     load-bearing reader rot apart, and nothing here would catch that.
   - After C1, the Stop hooks no longer agree on which text is "the last main-agent text". Two read the
     payload. Three still read the transcript: `handoff-claim-assert.sh:53`, `operator-readout.sh:1898`, and
     `dispatch-assert.sh:157` (windowed).
   - So operator-readout's close-verdict polarity check (`:1881-1901`, commented "Same selector as
     hooks/completion-assert.sh:258-261") can now read a different message from completion-assert at the
     same Stop. Before C1 both read the same stale record.
   - It is not a regression in the changed hooks, but it is a new disagreement between hooks on one concept.
   - **Cheapest fix:** a bats test that asserts the two payload-read blocks are byte-identical, plus a
     one-line comment fix at `operator-readout.sh:1884-1885`. A `hooks/lib` reader is the clean fix, and the
     `readlink` tier already in the hooks resolves a new lib without an install. It is optional at this size.
2. **The new suite never runs the key path under `/bin/bash`.** The rule
   `the-deployment-interpreter-is-not-the-one-on-your-path` asks for a run under the deployment interpreter,
   and a CC started from launchd resolves `#!/usr/bin/env bash` to 3.2. My edge runs and the designer's
   `run-hook32.sh` cover it outside the suite. **Fix:** add one `/bin/bash "$CA"` case with the key present.
3. **Test 4 (the latch hash) proves nothing on the unpatched copy.** It passes there too, because both reads
   come from the transcript. It is a valid guard on the patched copy only. The report says only tests 1, 2
   and 5 are RED, which is accurate, but the test name overstates what the RED/GREEN pair proves.
   **Fix:** add a case where the transcript record carries a trailing newline and the payload carries the
   trimmed text. That pins the `$( )`-strips-it claim in report §3.
4. **Hermeticity nit.** Tests 5 and 6 use a fixed `cwd` of `/tmp/adf`, outside `BATS_TEST_TMPDIR`. Use
   `$BATS_TEST_TMPDIR/adf`.

These are unmeasured behaviour effects. They follow from restoring designed behaviour, not from a defect, so
I do not count them against the fix:
- **More Stops reach the slow path.** On the replays, completion-assert took 3.0-3.8 s once it read the final
  and reached the ledger, against 0.3-0.5 s when it abstained at the gate (wall time at load average about
  500, measured). On my estimate (278 un-blinded misses minus 19 wrong-target blocks removed), about 259
  more Stops per 7.5 days run the ledger path. That is more exposure to the 5 s `timeout`, which F12 owns.
- **The shared `assert` cap (R3) fills sooner.** The 278 misses fall in 155 distinct sessions, and 28 of
  those have 3 or more misses (measured, `python3 -I` over `/tmp/r2-C1/replay/cases.json`). The designer's
  ~63 projected new fires (estimated) land in the shared `assert` budget, where MAX is 3. In those 28
  sessions, a later close is more likely to be `capped`, which is the mechanism behind the incident's
  suppressed ✅. C1 does not measure this, and C2 or F11 owns it.
- **Observability.** No IDL field records which source the hook read. If a future CC drops the key, the
  hooks go back to the racy path with no sign of it, and only the post-land census would show it. A
  `msg_src` field would make the §7 check direct, but it needs a check of the IDL tests first.

## 5. Conviction

**91%** that C1 is correct, regression-free in the two hooks it changes, and implementable as specified. The
measured basis:
- the diff applies to HEAD and `main`;
- 6 of 6 new tests pass, with 3 RED on the unpatched copy;
- 61/61, 8/8 and 185/185 on the suites I re-ran;
- bash 3.2 parse and runtime parity;
- shellcheck clean;
- process count lower;
- the binary semantics confirmed at the cited offsets.

It falls 2 points short of the designer's 93 for these reasons:
- the uncaught copy and the Stop hooks' new disagreement over the message (concern 1);
- no `/bin/bash` coverage of the key path inside the suite (concern 2);
- the unmeasured cap and slow-path interaction.

The required changes are concerns 1 to 4. Each costs a few lines of test or comment, and none changes the
design.
