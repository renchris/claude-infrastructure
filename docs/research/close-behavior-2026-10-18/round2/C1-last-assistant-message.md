# C1: Stop hooks prefer `last_assistant_message` over the transcript tail

Round 2, 2026-10-18. Candidate from axis 07 skeptic §S0 / §S4.2. Read-only in the repo; all prototypes and test
runs on copies under `/tmp/r2-C1/`. Every number is labelled measured (with the command) or estimated (with the
method).

Status: **complete**. Verdict: C1 clears 90% (93%) as a correctness fix for both Stop hooks. It is a precondition
for the incident fix, not the cure (§6). The pre-reboot run left only §0's first bullet, and `/tmp/r2-C1/` did not
survive the 16:34 reboot, so everything below was re-measured after it.

Answer first:
- (a) The 2.1.293 Stop payload carries `last_assistant_message`. CC builds it from the in-memory conversation,
  while the transcript is flushed by a 100 ms debounced queue (binary read; plus a live 2.1.220 capture).
- (b) The race is real and common. Over 1,818 Stops whose final and previous messages get different gate
  verdicts, 369 (20.3%) were judged on the previous one (measured; the gate replay agrees with the exact bash
  gate on 3,636/3,636 texts). rs05, rs13 and rs01 reproduce 6/6 offline.
- (c) The payload text has the same shape as the record: text blocks joined by `\n`, and `trim()` changes 0 of
  7,847 finals.
- (d) The patched copy passes every suite (185/185, 61/61, 8/8, 8/8, 9/9 and 9/9 with 9 skips). The new 6-test
  suite goes RED→GREEN.

## 0. Setup facts

- Installed binary (measured, `~/.claude-293/node_modules/.bin/claude --version`): `2.1.293 (Claude Code)`. The
  `claude` shell function (`~/.zshrc:457-509`) runs `$HOME/.claude-293/node_modules/.bin/claude`. The rs05
  final record itself carries `"version":"2.1.293"` (measured, `sed -n 167p <rs05 transcript> | jq -r .version`).
- Sandbox: `git archive HEAD | tar -x -C /tmp/r2-C1/repo` at `f12dd4b12` (the worktree has no tracked edits).
  The live hooks in `~/.claude{,-secondary,-quaternary}/hooks/` are symlinks into
  `~/Development/claude-infrastructure/hooks/`, and that checkout's MSG extractor is byte-identical to the
  sandbox's (measured, `diff <(sed -n '/Extract the LAST MAIN-agent text/,/no-assistant-text/p' …)`).
- No local CHANGELOG ships with the package (measured, `find ~/.claude-293 -maxdepth 4 -iname 'CHANGELOG*'`
  → none; `sdk-tools.d.ts` has 0 hits for `last_assistant_message`). The binary is a 236 MB Bun bundle, so the
  evidence below is read from the bundled JS by byte offset (`python3 -I`, read-only).

## 1. (a) Does the 2.1.293 Stop payload carry `last_assistant_message`? Yes, built from memory, not from disk

Measured: `python3 -I` byte search of `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
(dumps under `/tmp/r2-C1/bin-evidence/`).

1. **The Stop input object** (offset 195,022,749, function `yie`, the Stop/SubagentStop hook generator):

   ```js
   let he=b?ry(b):void 0,
       _e=he?ho(he.message.content,`\n`).trim()||void 0:void 0, …
   Te=g?{…,hook_event_name:"SubagentStop",…,last_assistant_message:_e,…}
       :{...Se,hook_event_name:"Stop",stop_hook_active:s,last_assistant_message:_e,...ke}
   ```

   - `ry` (offset 196,421,899): `function ry(e){return e.findLast((n)=>n.type==="assistant")}`.
   - `ho` (offset 196,478,311): `function ho(e,n=""){return e.filter((r)=>r.type==="text").map((r)=>r.text).join(n)}`.
   - `b` is the in-memory conversation: the main-session caller (offset ~200,504,588) is
     `yie(De, s.abortController.signal, void 0, k, s.agentId, s, w.messages, s.agentType, "blockable_turn_end")`,
     and `yie` forwards it as `messages:b` to the executor.
   - So the field is **the text blocks of the last in-memory assistant record, joined by `\n` and trimmed**, and
     it is **omitted** (JSON drops `undefined`) when that record has no text. It never touches the transcript file.
2. **The transcript is written through a 100 ms debounced queue.** The session-storage class has
   `FLUSH_INTERVAL_MS=100` (offset 196,608,143), and `scheduleDrain(){if(this.flushTimer)return;this.flushTimer=
   setTimeout(async()=>{…this.drainWriteQueue()…},this.FLUSH_INTERVAL_MS)}` (offset ~196,610,823). An appended
   record reaches disk no sooner than 100 ms after it is enqueued, plus the async append itself. The
   `blockable_turn_end` caller's preceding text (reply gate, StructuredOutput and hand-back enforcement, goal
   deferral) shows no `flush()` before `yie` is started (read of the ~2.5 KB before offset 200,504,588; a flush
   further up the call chain is not excluded by this read).
3. **Repo precedent.** Two hooks already read the field and document live captures:
   `hooks/subagent-stop.sh:30,93` (SubagentStop, "`.last_assistant_message` FIRST — measured") and
   `hooks/stop-failure-marker.sh:5,26,111` (StopFailure, "measured on 2.1.114 + 2.1.220"). `grep -rn
   last_assistant_message hooks/ lib/ bin/ tests/ scripts/` finds no Stop-event reader. The prior pass recorded
   the field on 2.1.284 by binary strings (`docs/research/claude-code-mods-2026-10-03/REPORT.md:34`).
4. **One live Stop payload on disk.** A grep of `~/.claude/state` and `~/.claude/autonomy` for
   `"hook_event_name":"Stop"` finds only test fixtures and docs (measured, `grep -rlF`, 250 s bound). The CC debug
   log `~/.claude-quaternary/debug/bb8ca621-8049-4822-98d5-14633bc1475e.txt:302` (cc_version 2.1.220, a prompt-type
   Stop hook echoes its input) holds a real one:
   `{…,"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"pong","background_tasks":[],"session_crons":[]}`.
   The transcript's final record is `"pong"` (measured, `jq` over `…/bb8ca621-….jsonl`), so the field and the record
   carry the same text.
   - The same log times the window. The final record is stamped 04:00:54.308Z. Stop-hook processing is logged at
     04:00:54.333Z (+25 ms), and the first command-hook output at 04:00:54.385Z (+77 ms). Both are earlier than the
     100 ms debounce could have written the record.
5. **Shape.** Over all 7,847 main-session Stops since 2026-10-11 (census in §2), the last assistant record before
   the `stop_hook_summary` carried text in 7,847 (100%). So on 2.1.293 the payload holds the final message on
   essentially every Stop, and the fallback is for older builds and fixtures. 0 of 7,847 final texts have leading
   or trailing whitespace (measured, `python3 -I` with the JS `trim()` character set). So CC's `.trim()` leaves
   the text byte-identical to the transcript record, and the latch hash does not depend on which source was read.

Verdict on (a): **yes, measured.** The field is present on 2.1.293, is built from memory rather than the file,
and has the same text as the transcript's final record.

## 2. (b) The race, reproduced offline and measured at population scale

### 2.1 The three named cases: what the hook read, against the final

Method: `/tmp/r2-C1/scripts/timeline.py` (record listing) and `/tmp/r2-C1/scripts/mkviews.py`, which writes
`<id>.pre.jsonl` (the transcript minus the final record, which is what the hook read if that record was still in
the write queue), `<id>.post.jsonl` (through the final record) and `<id>.lam.txt` (what 2.1.293 would send as
`last_assistant_message`). Each view was run through the **unmodified** hooks from `/tmp/r2-C1/repo`
(`/tmp/r2-C1/scripts/run-hook.sh`: every state seam goes to a fresh `/tmp/r2-C1/runs/r.*`, HOME is sandboxed,
`CC_BACKLOG_BIN` is an `[]` stub, `ANTIDEF_DECIDE_BIN=/nonexistent`, and cwd is a clean landed fixture repo).

| id | final record (ts, line 1) | last text record without it (line 1) | live IDL (completion-assert / anti-deference) | hook on `pre` | hook on `post` |
|---|---|---|---|---|---|
| rs05 | `5759497b…:167`, 06:04:16.097Z, "Yes to both, and they're really one job…" | `:145`, "There's a lot of prior work, including two load investigations…" | 06:04:16Z `no-close-tell` / 06:04:17Z `no-tell` | `no-close-tell` / `no-tell` | **fired** (D1, "An operator-only step is not an escape hatch…") / `no-tell` |
| rs13 | `7b65812a…:437`, 04:09:03.581Z, "Yes, it's worth improving…" | `:421`, "Found it. The bare "📬 peer mail" line is fixed text…" | 04:09:04Z `no-close-tell` / 04:09:04Z `no-tell` | `no-close-tell` / `no-tell` | **fired** (D4, "Your close names remaining work and then offers it…") / **fired** (`deference`, matched "Shall I") |
| rs01 | `58d3640a…:3380`, 17:30:31.607Z, "Yes, and cost is the smaller of the reasons…" | `:3363` (the PREVIOUS turn's final), "Drop the ASCII step…" | 17:30:32Z `no-close-tell` / 17:30:32Z `no-tell` | `no-close-tell` / `no-tell` | **fired** (D6, close contract "missing [good-to-close-verdict line-1-rung]") / `no-tell` |

Corrections to the brief's pointers. rs01's line in axis 07 §3 (`:3376`) is the operator's message; the final is
`:3380`. All three finals are `"version":"2.1.293"`.

Reading:
- In all three, the **pre** view reproduces every live IDL verdict exactly (6 of 6), and the **post** view
  changes 4 of the 6.
- Each hook logged its verdict within the same wall-clock second as the final record's timestamp. Per the
  `stop_hook_summary` rows, completion-assert ran 749 / 1,040 / 1,282 ms and anti-deference ran 1,283 / 919 /
  943 ms. So each hook's transcript read started a few hundred ms or less after the final record was created.
- The `post` dispositions depend on the sandbox ledger (clean, landed, `[]` backlog). The live ledger may have
  given a different arm, so only the gate and lexicon verdicts are claimed to transfer. Those were
  `no-close-tell`/`no-tell` on what the hook read, and past-the-gate/`deference` on the final.

### 2.2 Population: how often does a Stop hook judge the previous message?

Method (`/tmp/r2-C1/scripts/census.py`, `analyze.py`, `analyze2.py`; read-only). It covers every main-session
`stop_hook_summary` since 2026-10-11T00:00Z in the 1,047 transcripts under `~/.claude*/projects/*/` modified since
then. For each Stop it takes `final` (the last main text record before the summary) and `stale` (the text record
before that). Both get the completion-assert close-tell gate (`hooks/completion-assert.sh:355-397`). The window
starts after the gate's last edit (`afb9d93d2`, 2026-10-10; `git log -L` on `CLOSE=`, `CA_SETTLED=`,
`CA_VERDICT_NO=`). The live completion-assert IDL row is matched when it is the only row for that sid in
`[floor(final ts), summary ts + 1 s]`. A Stop **discriminates** when the two views get different gate verdicts.
Then the live verdict says which view the hook actually read.

Validation: the Python gate was checked against the exact bash gate (`/tmp/r2-C1/scripts/gate.sh` = hook lines
355-397, run with `bash`) on all 3,636 discriminating texts. They agree **3,636 / 3,636**.

| Measured (`python3 -I analyze2.py stops.jsonl`) | Stops |
|---|---|
| main-session Stops | 7,847 |
| no live IDL row in the window (5-s timeout kill, or unmatched) | 734 |
| pre-gate abstain (kill-switch, relay, …) | 106 |
| matched, both views get the same gate verdict | 5,188 |
| **matched and discriminating** | **1,818** |
| … live verdict = the final's | 1,449 |
| … **live verdict = the previous message's** | **369 (20.3%)** |

The 369, by what the hook did with the wrong message:
- **278 misses.** The final passes the gate, but the hook logged `no-close-tell` (271) or `no-assistant-text` (7,
  a first turn with no earlier text on disk).
- **19 wrong-target blocks.** The hook logged `fired`/`false-done` while the final would have abstained at the
  gate, so it blocked a turn over the previous message's words.
- **11 `latched-already-fired`.** After a block, it re-read the message it had just blocked, so the agent's
  answer to the block went unjudged.
- **The rest** were judged on the wrong message and abstained or capped downstream: `ledger-clean` 35, `capped` 22,
  `research-relay` 2, `genuine-blocker` 2.
- anti-deference corroborates this on a small n. Of the 7 Stops where only the final carries a `TELLS` phrase,
  2 logged `no-tell` (it read the previous message), 3 fired and 2 abstained as genuine.

Estimated: about 20% of all Stops are judged on the previous message. This extrapolates the discriminating
subset's 20.3% to all 7,006 matched Stops, on the assumption that flush timing does not depend on what the two
messages say. That is about 1,400 Stops in 7.5 days, of which only the discriminating ones change a verdict. A
start-time comparison could not sharpen this, because the IDL `ts` has 1-s resolution: the estimated hook-start
offset has a median of −0.10 s for stale reads against +0.05 s for final reads, inside the ±0.5 s noise.

A second mechanism gives the same symptom: a read that meets a half-appended last line, which jq rejects, so
`tail -1` returns the earlier record. The payload read removes both, so the design does not need to tell them
apart.

Conviction that the race explains rs05/rs13/rs01 rises from 70% (axis 07 §S0) to **95%**. The basis is the
mechanism in the binary, the 6/6 reproduction of the live verdicts, the 25-77 ms timing in the debug log, and
the 20% population rate. The remaining 5% covers the unexamined flush call further up the chain and the
IDL-to-Stop matching.

## 3. (c) Downstream use of MSG: is the payload text the same shape?

- **Same text, same shape.** Both sources are "text blocks of one assistant record joined by `\n`" (hook jq:
  `[.message.content[]? | select(.type=="text") | .text] | join("\n")`; CC: `ho(content,"\n")`). Both drop
  `thinking`/`tool_use` blocks. CC adds `.trim()`, which changes 0 of 7,847 finals (§1.5). Markdown, backticks
  and quotes reach the hook unchanged.
- **Quote stripping** (`MSG_UNQ`, `completion-assert.sh:441-442`): `sed -E 's/`[^`]*`//g; s/"[^"]*"//g;
  s/“[^“”]*”//g'` on the text. It is source-independent.
- **Line-1 logic** (`ca_first`/`ca_second`, `:375-381`) strips leading whitespace and skips blank lines, so a
  trimmed text gives the same first line.
- **`$( )` capture.** It strips trailing newlines on both paths (`MSG="$(… jq -r …)"`), so the two sources
  reach `HASH` (`:1557`, and `anti-deference-nudge.sh:594`) as identical bytes. The new bats test "the same
  message read from payload then transcript keeps one latch hash" pins this.
- **What differs.** Only which record: the payload is the record CC just produced, while the scan is whatever
  record was on disk. When the last in-memory assistant record has no text, CC omits the key (`||void 0`), the
  hook falls back to the scan, and today's walk-back behaviour (the P0-4a 74% blind-rate fix) is kept.
- **Other readers of the same tail.** `hooks/handoff-claim-assert.sh` and `hooks/operator-readout.sh` have the
  identical extractor (measured, `grep -ln 'select(.type=="assistant" and (.isSidechain != true))'`). They are
  outside C1's brief and are listed in §6 as follow-ons.

## 4. (d) Tests against the patched copy

All runs are on `/tmp/r2-C1/patched`. Both sandbox copies got a throwaway `git init` whose
`objects/info/alternates` points at `~/Development/claude-infrastructure/.git/objects`. That is a read-only
borrow, so `tests/stop-hook-forks-helpers.bash` `shf_old_tree` can `git show` its `SHF_BASE`. `cc-bats` deferred
the first attempt (rc 75, two other sessions held both slots). Note that `/opt/homebrew/bin/bats` reaches the
real engine through the `cc-bats` shim at `libexec/bats-core/bats`. The runners therefore retry on rc 75 and
never use the waiver. Each plan line `1..N` is asserted, per the lesson `a-gate-refusal-is-not-a-gate-result.md`.

| Suite (measured, `bash /tmp/r2-C1/scripts/run-bats.sh /tmp/r2-C1/patched patched`) | Plan | ok | not ok | skip |
|---|---|---|---|---|
| `tests/completion-assert.bats` | 1..185 | 185 | 0 | 0 |
| `tests/anti-deference-nudge.bats` | 1..61 | 61 | 0 | 0 |
| `tests/completion-assert-forks.bats` (process budget plus byte parity against `SHF_BASE`) | 1..8 | 8 | 0 | 0 |
| `tests/completion-assert-durations.bats` | 1..8 | 8 | 0 | 0 |
| `tests/completion-assert-assignee-shared-cwd.bats` | 1..9 | 9 | 0 | 0 |
| `tests/jev-anti-deference-arm.bats` | 1..9 | 9 | 0 | 9 ("deps not installed", the arm is retired) |
| `tests/operator-surface-scope.bats`, `why-tier.bats`, `plan-version-sid.bats` (sibling suites that drive the hooks) | 1..21, 1..16, 1..4 | 21, 16, 4 | 0 | 0 |
| `tests/research-relay-check.bats` run from `/tmp/r2-C1/patched` | 1..21 | 20 | 1 (test 21) | 0 |
| `tests/research-relay-check.bats` run from `/private/tmp/r2-C1/patched` (`/tmp/r2-C1/scripts/run-rrc.sh`) | 1..21 | 21 | 0 | 0 |
| **new** `tests/stop-last-assistant-message.bats`, patched | 1..6 | 6 | 0 | 0 |
| **new** suite on the **unpatched** copy (RED check) | 1..6 | 3 | **3** (tests 1, 2, 5: the race shapes) | 0 |

- **research-relay-check test 21 is a sandbox artifact, not this change.** It runs `router.py` directly and
  never runs either hook. `router.py:119` is `HERE = Path(__file__).resolve().parent`, `/tmp` is a symlink to
  `private/tmp` (measured, `readlink /tmp`), and the test expects `$REPO`, which is `/tmp/r2-C1/patched`.
  `router.py` is byte-identical in both copies (`diff -q`). Re-run from the copy's realpath
  `/private/tmp/r2-C1/patched`, the suite passes 21/21 (measured, the next row).
- **Process budget.** The forks suite reports 15 external calls on the no-close-tell path (budget ≤ 16), and its
  byte-parity tests pass. Counting jq starts for one Stop (`/tmp/r2-C1/scripts/count-jq.sh`, a PATH stub, rs13):

  | Hook | Unpatched, no key | Patched, no key | Patched, key present |
  |---|---|---|---|
  | completion-assert | 17 | 17 | 16 (the transcript-scan jq is gone) |
  | anti-deference | 8 | 8 | 7 |

  On rs01's 6.1 MB transcript, the scan that goes away takes 0.10-0.13 s, against 0.01-0.02 s for the payload
  read (measured, `/usr/bin/time -p`, load average ~250).
- **Lint.** Bare `shellcheck` (the land gate's invocation, per the lesson `a-gates-invocation-is-part-of-its-contract.md`)
  reports 0 findings on both hooks, before and after.
- **Patched replay of the three cases** (`run-hook.sh /tmp/r2-C1/patched … <id>.pre.jsonl <id>.lam.txt`). The
  transcript is still one record early and the payload carries the final. The result equals the `post` column
  of §2.1 in all 6 cases: rs05 completion-assert fires D1, rs13 fires D4 and `deference`, rs01 fires D6, and the
  other three stay silent. With the key absent, the patched hook returns today's `no-close-tell`/`no-tell` (6/6).

## 5. The exact diff

`/tmp/r2-C1/C1-full.diff` (198 lines). It was checked with `git apply --check` and then applied to a fresh
`git archive HEAD` of the two hooks, and the result is byte-identical to the tested files (`diff -q`). Hooks:

```diff
--- a/hooks/completion-assert.sh
+++ b/hooks/completion-assert.sh
@@ -276,13 +276,28 @@
 # six other call sites' ledger.
 export WRAP_TRANSCRIPT="$TP"
 
-# ── Extract the LAST MAIN-agent text: skip sidechain (subagent) records, and walk back past a
-#    tool_use-only / metadata tail to the last assistant record that actually carries text
-#    (streaming; per-record compact-JSON keeps multi-line text on one line for tail -1). ──
-LASTJSON="$(jq -c 'select(.type=="assistant" and (.isSidechain != true))
-                   | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
-                   | select(. != "")' "$TP" 2>/dev/null | tail -1 || true)"
-MSG="$(printf '%s' "$LASTJSON" | jq -r '. // empty' 2>/dev/null || true)"
+# ── Extract the LAST MAIN-agent text. The Stop payload's `last_assistant_message` FIRST ──
+# Claude Code builds that field from the IN-MEMORY conversation (2.1.293: the text blocks of the
+# last assistant record, joined by "\n" and trimmed; the key is omitted when that record has no
+# text). The transcript is written through a 100 ms debounced queue, so a scan of the file at
+# Stop can end one record early and judge the PREVIOUS message: measured on 1,818 Stops whose two
+# candidate messages get different gate verdicts, 369 (20%) logged the verdict of the earlier one
+# (docs/research/close-behavior-2026-10-18/round2/C1-last-assistant-message.md). The `case`
+# keeps a payload without the key (an older CC, every fixture) at zero extra processes.
+# FALLBACK, unchanged: skip sidechain (subagent) records, and walk back past a tool_use-only /
+# metadata tail to the last assistant record that actually carries text (streaming; per-record
+# compact-JSON keeps multi-line text on one line for tail -1).
+MSG=""
+case "$input" in *'"last_assistant_message"'*)
+  MSG="$(printf '%s' "$input" | jq -r 'if type == "object" and (.last_assistant_message | type) == "string"
+                                       then .last_assistant_message else empty end' 2>/dev/null || true)" ;;
+esac
+if [ -z "$MSG" ]; then
+  LASTJSON="$(jq -c 'select(.type=="assistant" and (.isSidechain != true))
+                     | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
+                     | select(. != "")' "$TP" 2>/dev/null | tail -1 || true)"
+  MSG="$(printf '%s' "$LASTJSON" | jq -r '. // empty' 2>/dev/null || true)"
+fi
 [ -n "$MSG" ] || abstain "no-assistant-text"
 
 # ── ARM R — THE RESEARCH RELAY CHECK (wave B1; REPORT.md §4.4, §8 item 6) ─────────────────────
--- a/hooks/anti-deference-nudge.sh
+++ b/hooks/anti-deference-nudge.sh
@@ -152,14 +152,26 @@
 # lets it serve one. Absent (or unreadable) ⇒ that script computes exactly as it always has.
 export WRAP_TRANSCRIPT="$TP"
 
-# ── (P0-4a) Extract the LAST MAIN-agent text: skip sidechain (subagent) records, and walk back
-#    past a tool_use-only / metadata tail to the last assistant record that carries text (the
-#    G-P11-1 343c6e77 shape defeated the old tail-1 → 74% no-assistant-text blind rate). Streaming
-#    (no slurp); per-record compact-JSON keeps multi-line text on one line for tail -1. ──
-LASTJSON="$(jq -c 'select(.type=="assistant" and (.isSidechain != true))
-                   | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
-                   | select(. != "")' "$TP" 2>/dev/null | tail -1 || true)"
-MSG="$(printf '%s' "$LASTJSON" | jq -r '. // empty' 2>/dev/null || true)"
+# ── Extract the LAST MAIN-agent text: the Stop payload's `last_assistant_message` FIRST. It is
+#    built from the in-memory conversation; the transcript is written through a 100 ms debounced
+#    queue, so a file scan at Stop can return the PREVIOUS message (the reason, measured, is in
+#    hooks/completion-assert.sh at its MSG extraction; same read, same fallback). A payload
+#    without the key costs no extra process. ──
+MSG=""
+case "$input" in *'"last_assistant_message"'*)
+  MSG="$(printf '%s' "$input" | jq -r 'if type == "object" and (.last_assistant_message | type) == "string"
+                                       then .last_assistant_message else empty end' 2>/dev/null || true)" ;;
+esac
+# ── (P0-4a) FALLBACK: skip sidechain (subagent) records, and walk back past a tool_use-only /
+#    metadata tail to the last assistant record that carries text (the G-P11-1 343c6e77 shape
+#    defeated the old tail-1 → 74% no-assistant-text blind rate). Streaming (no slurp); per-record
+#    compact-JSON keeps multi-line text on one line for tail -1. ──
+if [ -z "$MSG" ]; then
+  LASTJSON="$(jq -c 'select(.type=="assistant" and (.isSidechain != true))
+                     | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
+                     | select(. != "")' "$TP" 2>/dev/null | tail -1 || true)"
+  MSG="$(printf '%s' "$LASTJSON" | jq -r '. // empty' 2>/dev/null || true)"
+fi
 [ -n "$MSG" ] || abstain "no-assistant-text"
 
 # ── (A) Deference tells on DRIVABLE work (corpus-validated; boundaries guard the substring traps:
```

The new test file `tests/stop-last-assistant-message.bats` (117 lines) is the third file in `C1-full.diff`. It
has six tests:
1. A busy transcript plus a done payload over an unlanded repo: fires.
2. A done-claim transcript plus a busy payload: `no-close-tell`. This is the wrong-target block removed.
3. `""`, `null`, `7`, `["x"]` and `{"t":"x"}` all fall back to the transcript.
4. The same message read from the payload and then from the transcript gives `latched-already-fired`, so the
   latch hash is the same.
5. anti-deference fires on a payload "Say the word…" over a busy transcript.
6. anti-deference falls back on `""`, `null` and `7`.

Negations use `! fired "$output" || false`, the repo's errexit-safe form. A bare `! cmd` never fails a bats body:
the first draft's RED run passed test 2's negation for exactly that reason, and it was fixed before the counts
above.

## 6. Design verdict

**Design.** Both Stop hooks take `MSG` from the payload's `last_assistant_message` when the key is present, is a
string, and is non-empty. Otherwise they run today's transcript walk-back byte for byte. No arm, regex, latch,
cap, IDL field or message text changes. The hooks still judge "the last main-agent text". Only the source changes:
the record CC just produced, instead of whatever record was on disk when jq read the file.

Constraint check:
1. **Silent when nothing drivable remains.** No new arm and no new message. A final with nothing drivable
   abstains exactly as the arms are designed to. The fix also removes 19 measured blocks per 7.5 days that fired
   on the previous message's words.
2. **Never blocks a genuine ⛔ or a stated park.** `GENUINE`, the class-C/`cc-decide` carve-outs and the
   kill-switch are unchanged, and they now read the message that contains the ask. Before the fix, a genuine ask
   in the final could miss the carve-out while the previous message convicted.
3. **No settings.json edit.** The field already arrives on every Stop. Both hooks stay `Stop`-only in all four
   live `settings.json` files (measured, `jq`, read-only).
4. **Rule text.** Unchanged, so the resident budget is ±0.
5. **The six files owned by another session.** None of them is touched.
6. **One matcher per concept.** No matcher changes. The extractor was already duplicated in four hooks. C1 adds
   the same read to two of them. Hoisting a `stop_message` reader into `hooks/lib/` for all four is a separate
   refactor.

**Effect (estimated from §2.2, which is measured).**
- About 20% of all Stops are currently judged on the previous message. The fix brings that to ~0 whenever CC
  sends the key, which was every one of the 7,847 Stops sampled.
- In the 7.5-day window it would have:
  - un-blinded 278 gate misses;
  - removed 19 wrong-target blocks;
  - let 11 post-block answers be judged, where today the hook re-reads the blocked message.
- Expected extra fires come from the arms as they are. Among final-read Stops that passed the gate, 182 of 799
  (22.8%) fired, which projects ~63 new fires over the 278 un-blinded misses (estimated), against the 19
  wrong-target blocks removed. Those fires carry the existing arms' precision. rs01 shows the cost: a legitimate
  value fork gets the D6 shape nudge ("lead with the good-to-close verdict line"), which asks for a rewrite of
  line 1, not for the decision to be overridden.
- On the incident set: rs13 (a clear defect) is caught by both hooks, and rs05 is caught in the sandbox (D1;
  the live outcome depends on the backlog read). It does **not** address the incident's ✅ close, which
  completion-assert read correctly and capped (README R3). It also leaves rs04/rs14, the 5-s timeout kills: 734
  of 7,847 Stops (9.4%) have no live IDL row.

**Conviction: 93% that C1 is correct and net-positive to land as specified.**
- The mechanism is measured three ways: in the binary, in a live capture, and as a 20% population rate.
- The fix is reproduced offline 6/6 and RED→GREEN in the new suite. All six existing suites of the two hooks are
  green. The process count is unchanged without the key and one lower with it.
- The 7% is:
  - (i) the 2.1.293 payload's in-memory semantics come from reading the bundled code, with a live capture only on
    2.1.220;
  - (ii) the ~63 projected new fires inherit arm precision that C1 does not measure;
  - (iii) the IDL-to-Stop matching assumption behind the 20%.
- As a fix for the close-behavior incident itself, C1 is a precondition, not a cure. The README's R1 is
  untouched.

## 7. Operator-only steps

None required. No `settings.json` change, no migration, no new lib, so there is nothing for install.sh to link.
The change lands as an ordinary edit to two tracked hooks plus one new suite. The live hooks are symlinks into
the main checkout, so it takes effect on the fast-forward.

Recommended post-land check (agent-runnable, read-only): after about 24 h, re-run `census.py` → `analyze2.py`
with `SINCE` set to the land time. The `saw stale` row should fall from about 20% of discriminating Stops to
about 0. Any residue would mean CC omitted the key, or sent a different record.

## 8. Open risks and follow-ons

1. **2.1.293 semantics are read from code.** The live capture is 2.1.220. If a future CC sent a non-final record
   in the key, the hooks would judge it. The fallback guards absence, not a wrong value. The §7 census re-run is
   the check.
2. **Arm precision is inherited.** About 63 projected new fires per 7.5 days fleet-wide (estimated). They are
   the right message hitting today's predicates, D6 on legitimate forks included (rs01).
3. **Same race in three more Stop readers, not changed here:**
   - `hooks/handoff-claim-assert.sh:53`;
   - `hooks/dispatch-assert.sh:157` (a timestamp-windowed tail read);
   - `hooks/operator-readout.sh:1898`.

   Each would take the same 5-line read. If all four sites change, a shared `hooks/lib` reader is the
   one-matcher-per-concept form.
4. **The 5-s timeout leg is untouched.** 734 of 7,847 Stops (9.4%) left no completion-assert IDL row. C1 saves
   one transcript scan, 0.10-0.13 s on a 6 MB transcript, which is not a fix for that.
5. **Interpreter.** `/bin/bash` 3.2 runs the patched hooks on rs13 with the same dispositions as Homebrew bash
   (measured, `/tmp/r2-C1/scripts/run-hook32.sh`). The `case` sits at top level, not inside `$( )`.

Artifacts (all under `/tmp/r2-C1/`, not tracked):
- `C1-full.diff` (the patch);
- `patched/` and `repo/` (the sandbox copies);
- `replay/stops.jsonl` (the 7,847-Stop census), `replay/cases.json` (1,818 discriminating Stops) and
  `replay/bash-gate.tsv` (the exact-gate validation);
- `replay/rs0{1,5}.*` and `replay/rs13.*` (the views);
- `bats/` (TAP output);
- `bin-evidence/` (binary excerpts);
- `scripts/` (every script named above).
