# Gap 4: does the recommended build apply "test the consumer, measure silence against expected fires" to its own new branches?

Date 2026-09-27. Repo `claude-infrastructure` at `fe059ffa5`. Read-only everywhere; scratch in `/tmp/tm-research/gap4/`.
Labels: **MEASURED** = I ran or read it this pass (command named). **CLAIMED** = a doc says so. **ESTIMATED** = method stated.

## 0. Answer

**Mostly no.** SYNTHESIS §3.3 states the lesson (hooks log every exit path, and silence is measured
against expected fires) (SYNTHESIS:183-184). It then wires it only into pre-existing hooks, using two
denominators: SessionEnd index lines and `nudge-*.count` (SYNTHESIS:197-198). The new branches (#6, #10, #14) and the
new tool (#4) each sit behind a fail-open construct that makes "broken" and "healthy, nothing matched"
the same observation. None of them names an independent expected-fire denominator. Only #6 names a
consumer-side delivery check, and that check is a one-time probe (SYNTHESIS:316-317).

This pass MEASURED five further problems the synthesis does not cover, each of the same failure class.
1. **Deploy class.** New `hooks/lib/*.tsv` and `*.jq` files are never linked live. New `hooks/lib/*.py`
   files are not repaired by deploy-live.
2. **CLAUDE variant.** The model-facing CLAUDE.md edits target a variant that about 7% of the last
   day's transcripts load.
3. **Log location.** `$CFG/state` logs split across 4 physical directories.
4. **Event name.** log-bash serves two events, and CC drops or rejects a mismatched `hookEventName`.
5. **Post-hoc advisory.** All 266 of 266 PreToolUse context attachments sampled in two days reached
   the model in the same request as their tool result. #10's advisory is therefore always post-hoc, and
   the action it asks for ("discard the new one") needs a Bash `rm` that nothing auto-allows.

**Disposition impact.** No item changes disposition. Two items need their plans re-scoped, and several
target-file lists need correcting:
- #3 grows from S to S-M;
- #6's 2-week holdout is statistically powerless as an efficacy test (ESTIMATED), so it must become a
  liveness gate first;
- the target-file lists of #4, #10, #12 and #27 must add `CLAUDE.global.slim.md`.

Details and acceptance criteria follow.

---

## 1. Branch-by-branch audit (what makes each one silently dead)

| Item | New branch / surface | Fail-open construct that hides breakage (MEASURED, file:line) | Independent expected-fire denominator in design? | Rendered-output / consumer test in design? | In #3 SILENT? |
|---|---|---|---|---|---|
| #6 | scan in `bash-output-offload.sh` | Whole body is one `python3 -c` with `except Exception: sys.exit(0)` and `2>/dev/null` (`hooks/bash-output-offload.sh:26-29,70-74`). A scan placed "before its size early-exit" (`:39-40`) that raises kills the **existing offload too**, silently. | No. It logs hits only (`lesson-hits.jsonl`, SYNTHESIS:315), and hits are rare. | A one-time nonce probe (SYNTHESIS:316-317). There is no bats test of the rendered hook JSON. | No |
| #6 | scan in `log-bash.sh` (PostToolUseFailure `.error`) | The hook prints nothing today and always exits 0 (`hooks/log-bash.sh:54-56`). The same script is registered for **both** PostToolUse and PostToolUseFailure (settings.json, MEASURED with jq). | No | Probe only | No |
| #10 | new-file branch in `backup-before-write.sh` before `:82-83` | `set -uo pipefail`, no `-e` (`:13-14`); a missing jq means a silent pass (`:17-19`). The python helper has a 2 s timeout and fails open (SYNTHESIS:418). The EXIT trap emits a rewrite-only JSON when nothing else was emitted (`:75-79`), so a branch that prints outside `_bbw_out` yields **two JSON objects**. | No. It logs to `$CFG/state/mem-neighbours.jsonl` (SYNTHESIS:418), which splits 4 ways (§2.4). | No | No |
| #14 | `import transcript_norm` in the session-index python blocks | "inline fallback if the import fails" (SYNTHESIS:511). The fallback **is the old contaminated logic**, so a failed import silently reverts the fix. The blocks are `python3 -c "..."` in bash (`hooks/lib/session-index-helpers.sh:641-699,701-~800,816-~920`). | No | No. Planned tests cover `tests/transcript-norm.bats`, i.e. the producer lib, not the consumer function. | No |
| #4 | `bin/cc-memory-search` | A pull tool. Its failure modes are "never invoked" (instruction not delivered, tool not on PATH) and "invoked, 0 hits" (scope resolves to the wrong store). Neither is an error the model reports. | No. "Log invocations for #15" (SYNTHESIS:243) is a numerator. | #5 invokes the retriever "exactly as its hook invokes it" (SYNTHESIS:269), but on a frozen snapshot, not the live store, and not nightly. | No |

---

## 2. MEASURED evidence gathered this pass

### 2.1 PreToolUse context reaches the model only with the tool result
`gap4/order.py` scans all `.jsonl` transcripts modified in the last 2 days, across the 4 physical
roots, and places each `attachment.type == "hook_additional_context"` relative to its `tool_use` and
`tool_result` lines by `toolUseID`.
- 522 transcripts in 8.2 s wall.
- **PreToolUse:** 266/266 attachments are recorded after their `tool_use` and before its
  `tool_result`, which is the next request the model sees.
- **PostToolUse:** 94/94 attachments are recorded after the result. 0 unmatched.
- **PostToolUseFailure:** 0 attachments. None of our hooks emits on that event today, so the #6
  log-bash arm would be the first user of an unexercised channel.

What this means:
- The model has no turn between a tool_use and its hook, so a PreToolUse `additionalContext` cannot
  influence the call it annotates. This confirms fit note `fit-whole-store-neighbour-advisory.notes.txt:8`
  and `_cc_hooks.md:1003` ("next to the tool result").
- The existing `OVERWRITE GUARD: You are about to OVERWRITE …` (`hooks/backup-before-write.sh:248`)
  already arrives after the overwrite. There were 8 such attachments in the sample.

Attachments carry `hookName`, `hookEvent` and `toolUseID`. Every hook payload carries `tool_use_id`
(`_cc_hooks.md:776,2004,2106`). So **a hook row that records `tool_use_id` can be joined exactly to what
the harness recorded as delivered.** That is a durable consumer-side test that needs no live model run.

### 2.2 CC's handling of a mismatched `hookEventName` (static read, CC 2.1.278 strings)
- `_cc_strings.txt:195712,295233`: `Hook returned incorrect event name: expected '…' but got '…'` (thrown).
- `_cc_strings.txt:191582,294055`: `hookSpecificOutput_event_mismatch` (dropped).
- `log-bash.sh` is registered for PostToolUse(Bash) and PostToolUseFailure(Bash) (jq over
  `~/.claude/settings.json`). A pointer emitted with a hard-coded `"PostToolUse"` on a failure payload
  is rejected or dropped. That payload is exactly the case #6's log-bash arm exists for.
- Also unprobed: whether PostToolUse honours `additionalContext` **alongside** `updatedToolOutput` in
  one object. The offload already emits the latter (`bash-output-offload.sh:69`).

### 2.3 New lib files are dark by deploy class
- `install.sh:340` links only `hooks/lib/*.sh` and `hooks/lib/*.py`. Its comment at `:336-339` records
  the kill-selection.py precedent, where the hook "was silently inert on the very box it shipped for".
  **`hooks/lib/lesson-symptoms.tsv` (#6) and `hooks/lib/inject-sanitize.jq` (#7) would never be linked
  into `~/.claude/hooks/lib/`.**
- `scripts/deploy-parity-assert.sh:551-552`: `hooks/lib/*.sh` is want=1, then `hooks/*/*` is want=0. So
  a new `hooks/lib/*.py` (#10 `memory_neighbours.py`, #14 `transcript_norm.py`) is not in deploy-live's
  MISSING-repair set. It appears live only after an install.sh advance.
- Live hooks are per-file symlinks into the checkout (`ls -la ~/.claude/hooks/`). A caller that
  **dereferences** its own path finds the new lib in the checkout at once. That is the pattern at
  `hooks/backup-before-write.sh:101-119` (`_mib_deref`), whose comment names this exact silent-inert
  shape. `bash-output-offload.sh` has no path resolution today. The session-index helpers resolve
  through a single `readlink` (`session-index-helpers.sh:40-47`).
- Our own store already records the lesson: memory topic `self-deploying-fix-inert-for-its-own-deploy.md`.

### 2.4 `$CFG/state` splits across 4 physical directories
- `~/.claude-next/state` links to `~/.claude/state`. `~/.claude-{secondary,tertiary,quaternary}/state`
  are real directories (MEASURED with `readlink`/`-d`).
- #10 logs to `$CFG/state/mem-neighbours.jsonl` (SYNTHESIS:418). #3's SILENT denominator
  `nudge-*.count` also lives in `$CFG/state` (`hooks/memory-nudge.sh:57-63`).
- A nightly alarm reading one path sees one account's share. In the last day, transcripts by root were
  `~/.claude` (includes next) 20, secondary 68, tertiary 189, quaternary 9 (MEASURED with
  `find -mtime -1`). The main root is about 7%.
- The heartbeat fit note already warned about this (`fit-memory-hook-heartbeats.notes.txt:31`), but it
  did not reach #10's design.

### 2.5 The CLAUDE.md consumer: 4 of 5 roots load the slim variant
- `~/.claude-{next,secondary,tertiary,quaternary}/CLAUDE.md` link to `~/.claude/CLAUDE.slim.md`, which
  is byte-identical to `CLAUDE.global.slim.md` (MEASURED with `cmp`).
- Its rule sits at `CLAUDE.global.slim.md:47` ("Grep MEMORY.md first…"), not at `CLAUDE.global.md:103`.
- The target lists for #4 (SYNTHESIS:63,240), #10 (:69,419), #12 (:71,463) and #27 (:86) name only
  `CLAUDE.global.md`. As written, those edits reach the root that held 20 of 286 transcripts in the last day.
- This is a producer-edited, consumer-unverified change, the same class as TM's MCP instructions
  truncated at 2,048 chars (SYNTHESIS:750-751).

### 2.6 Expected-fire volumes (to size denominators)
- **New topic files by birthtime:** 67 in 7 days and 132 in 14 days fleet-wide (MEASURED:
  `gap4/births.py`, realpath-deduped stores, MEMORY.md excluded). By store over 14 days: reso 54,
  infra 34, sevenrooms-bridge 9. Birthtime is an upper bound, because an atomic-replace rewrite resets it
  (not checked). The Write share of creations is about 82% (`fit-whole-store-neighbour-advisory.notes.txt:15`).
- **Bash calls:** `bash-execution.log` held 35,029 calls over roughly 3.2 days (09-24 19:09 → 09-27),
  with a peak of 12,718 on 09-26 (MEASURED with grep). It is size-rotated to `.gz` roughly every 3-5
  days, so older windows must read the `.gz` files.
- **Bash greps of memory paths:** 210 in the same window (MEASURED; the regex
  `(grep|rg)…(MEMORY\.md|/memory/|docs/lessons)` is rough).
- **Failure `.error` text:** it carries "Exit code N" plus the flattened command output, up to about
  11 k chars (MEASURED: `Exit:` field lengths in bash-execution.log). The log-bash arm therefore has
  text to scan.
- **Offloaded results:** 37 offload-marked tool results in the last day's 806 MB of transcripts
  (MEASURED: `grep -o 'bash-output-offload: [0-9]* lines'`, 19 s). This is a delivery signal for the
  existing offload, and a cost reference for a nightly replay.
- **#6 fire rate:** 57 foreign-emitter output hits over 09-05..09-27 in `relearning-hits.tsv`, after
  excluding the self-emitter slugs `a-gate-refusal…` (174) and `a-landed-verdict…` (22). Of the 57, 22
  are core.bare (fading) and 20 are tab-IFS (already land-gated). So #6 fires about 36 times per 2 weeks
  **before** per-(session, slug) dedup (ESTIMATED from the census; its matchers are not the future tsv).

### 2.7 #6's 2-week holdout has almost no power (ESTIMATED)
- About 36 fires in 2 weeks with a 20% holdout gives about 7 control and 29 treated.
- Baseline "opened the lesson" is 4% (SYNTHESIS:290).
- Even a lift to 9/29 against 0/7 gives a one-sided Fisher p of 0.106; 6/29 gives 0.244. Only 12/29
  (41%) reaches 0.041. Computed in the python block in this pass's shell log.
- So "no effect at 2 weeks" is the expected reading **whether the branch is dead, delivered-but-ignored,
  or modestly effective**. The holdout cannot tell these apart unless liveness and delivery are
  established first and the window runs until each arm has enough events.

### 2.8 #10's requested action is friction-gated
- The advisory text asks the model to "Edit that file and discard the new one" (SYNTHESIS:416-417).
  Discarding means `rm /Users/…/.claude/projects/<slug>/memory/x.md`.
- `hooks/rm-safe-allowlist.sh:8-12` auto-allows only regenerable build/cache targets under the repo or
  `/tmp`. An absolute path outside the repo "falls through". There, `defaultMode: auto` (MEASURED, jq)
  hands the call to the auto-mode classifier or an ask prompt.
- Whether the model completes the discard is therefore uncertain even when it agrees. Nothing in the
  design observes it.

### 2.9 Precedents in our own alarm that the new branches would violate
- **New reasons read as healthy.** `scripts/idl-abstain-alarm.sh:26`: "New/unclassified reasons default
  to DORMANT". The BLIND vocabulary is a fixed list (`:128-131`). A new branch's could-not-observe
  reason (e.g. `no-symptom-table`, `neighbour-lib-missing`, `norm-import-failed`) that is not added
  there reads green DORMANT-100. This matches memory topic `new-enum-member-falls-into-fail-closed-default`,
  cited at `:256`.
- **Housekeeping rows mask dead branches.** `:245-256`: evaluations-only denominator. waiting-recycle
  read HEALTHY on 4 `gc` rows while its actuator fired 0 times in 14 days. A branch that logs under its
  host hook's name can be masked the same way by the host's other rows.
- **A missing denominator must say UNKNOWN.** `:143-157`: the census denominator prints UNKNOWN
  rather than nothing, because "a MISSING denominator line and a denominator of 100% are the same
  observation". The new SILENT class needs the same rule per branch.
- **Delivery changes across versions.** `docs/research/cross-session-mail-2026-07-20.md:137`: the same
  documented field was INERT on 2.1.207 and live on 2.1.220, and "a doc citation dates neither
  direction. Probe the running binary." A one-time probe (#6 step 4) therefore expires with the binary.
- The store already holds `positive-control-the-denominator`, `fail-loud-into-a-log-nobody-reads-is-silent`,
  `fixture-shape-parity-with-real-producer` and `fail-safe-default-mimics-the-healthy-state`. The build
  does not need a new lesson. It needs to obey these.

---

## 3. Acceptance criteria to add (no new items)

### Cross-cutting (apply to #6, #7, #10, #14)
- **X1. Lib resolution.**
  - Every new lib consumer resolves its lib through a dereferenced self-path (the `_mib_deref` pattern,
    `backup-before-write.sh:107-119`), never through `~/.claude/hooks/lib`.
  - A bats case runs the hook **through a symlink placed in a temp dir** and asserts the lib was found.
  - Alternatively, extend `install.sh:340` and `deploy-parity-assert.sh:551` to `*.tsv` and `*.jq` and
    make `*.py` want=1. That is a wider change and must be operator-approved.
- **X2. Branch-level IDL names.** Each branch logs under its own name, e.g.
  `bash-output-offload:lesson`, `log-bash:lesson`, `backup-before-write:neighbours`,
  `session-index:norm`, `cc-memory-search`. A host hook's other rows then cannot mask the branch (alarm `:245-256`).
- **X3. BLIND vocabulary lands in the same change** as the reasons that use it. Add each branch's
  could-not-observe reasons to `_default_blind` (`idl-abstain-alarm.sh:128`) in the same commit. Pin
  them with a vocab check, as `--vocab-lint` already does for reap.
- **X4. Shared log location.** State and log paths use `$HOME/.claude/...` (shared), never `$CFG/state`,
  **or** the alarm sums all 4 physical state dirs. The #3 selftest covers a row written under a
  non-main `CLAUDE_CONFIG_DIR`.
- **X5. Denominator independence.** Each branch's denominator is computed from a source the branch does
  not write (filesystem, transcripts, another hook's log). A denominator derived from the branch's own
  rows cannot detect the branch's death.

### #3 memory-hook-heartbeats: generalise SILENT into an expected-fires registry
- Replace the two hard-coded denominators (SYNTHESIS:197-198) with a small declarative table,
  `scripts/idl-expected-fires.tsv`, with columns `branch  denominator-fn  window  D_min  ratio_floor`.
  Seed rows:

| branch | denominator (independent source) | window | SILENT if | DEGRADED if |
|---|---|---|---|---|
| harvest-skill-end | SessionEnd index lines (existing) | 7 d | rows < NMIN while D ≥ D_min | — |
| memory-nudge | `nudge-*.count` summed over **all 4** state dirs | 7 d | same | — |
| backup-before-write:neighbours | new `memory/*.md` + `docs/lessons/*.md` files by birthtime (fleet ≈ 67/wk, §2.6) | 7 d | D ≥ 10 and rows = 0 | rows/D < 0.5 (Write share ≈ 0.82) |
| bash-output-offload:lesson + log-bash:lesson | nightly **transcript replay**: the same tsv and dedup over the last 24 h of tool_result text in all 4 roots (≈ 20-60 s, from the 19 s single-literal grep in §2.6) | 7 d | replay_expected ≥ 3 and delivered rows = 0 | rows/replay < 0.5 |
| session-index:norm | `Indexed session` lines in session-index.log | 1 d | `norm=lib` rows = 0 while D ≥ 5 | any `norm=fallback` row (BLIND) |
| cc-memory-search | `cc-memory-search` commands in bash-execution.log(+.gz); new topic files; memory greps (210 per ~3 days) | 7 d | memory greps + new files ≥ 50 and rows = 0 | tool rows < bash-log invocations (crash before log); Exit 127 > 0 |

- A denominator that cannot be computed prints `denominator: UNKNOWN (<why>)` for that branch. It is
  never omitted and never read as HEALTHY (alarm `:153-157` rule).
- The selftest gets, per registry row, one RED case (branch silent, denominator positive → SILENT) and
  one UNKNOWN case (denominator source absent → UNKNOWN, exit 0).
- **Size.** S → S-M (ESTIMATED: about 60-100 extra lines for the table reader and five denominator
  functions, plus about 10 selftest cases).

### #6 symptom-to-lesson (both arms)
1. **Isolation.** The scan runs in its own `try` inside the offload python. On exception it writes one
   `failed` row with the exception class and continues to the unchanged offload path. A bats case forces
   a scan exception (an unreadable tsv) and asserts that the offload JSON for a >8,000-char output is
   still emitted byte-identically.
2. **One JSON object.** When both offload and a pointer fire, stdout is exactly one object whose
   `hookSpecificOutput` carries `updatedToolOutput` **and** `additionalContext`. A bats case asserts
   `jq -s length == 1`.
3. **Event-name echo.** log-bash emits `hookEventName` equal to the payload's `hook_event_name`.
   Rendered-output bats cover both PostToolUse and PostToolUseFailure payloads, using captured **real**
   payload shapes (fixture-shape-parity; `log-bash.sh:26-33` records a fixture that synthesised
   `exitCode` and certified a dead field).
4. **Symptom-table positive control.** Each evaluation logs `rows_loaded`. `rows_loaded == 0` is the
   BLIND reason `no-symptom-table`. A nightly **live-path canary** pipes a fabricated payload containing
   one canary literal through `~/.claude/hooks/bash-output-offload.sh` (the deployed symlink, not the
   checkout path) and asserts a pointer in the rendered JSON. Canary rows are tagged and excluded from
   the holdout.
5. **Consumer-side delivery, recurring.** Every hit row records `tool_use_id`. The nightly replay joins
   each row to a `hook_additional_context` attachment with the same `toolUseID` whose content contains
   the slug. It reports `delivered/emitted`, and `< 0.9` pages. This replaces the one-time probe as the
   standing check; keep the probe as the day-0 gate, including the combined `updatedToolOutput` +
   `additionalContext` case and PostToolUseFailure, which has 0 live uses today (§2.1).
6. **Holdout re-scoped.**
   - Holdout slugs still write a row (`arm: holdout, delivered: false`) and a replay-expected count, so
     the control arm has a denominator.
   - The holdout clock starts only after 7 days of liveness (SILENT-free), delivery ≥ 0.9 and a green canary.
   - The efficacy verdict waits for ≥ 15 control events. That is about 2 months at the §2.6 rate
     (ESTIMATED), not 2 weeks.
   - A 2-week read is labelled "liveness only".

### #10 whole-store-neighbour-advisory
1. **Every exit path logs** from the **bash** branch, not the python helper, so a python crash or timeout
   still leaves a row: `fired` (neighbours shown), `abstained:kill-switch` (DORMANT),
   `abstained:empty-pool` (DORMANT), `abstained:neighbour-lib-missing` (BLIND), `failed:timeout`,
   `failed:rc=N`.
   - The row carries `tool_use_id`, the canonical new path, and the top-2 neighbour paths.
   - It goes to `$HOME/.claude/state/mem-neighbours.jsonl` (X4), not `$CFG/state`.
2. **Rendered-output bats.**
   - A Write to a symlinked-spelling new memory path yields exactly one JSON object carrying **both**
     `updatedInput` (the canon rewrite, `:48-61`) and `additionalContext` (the neighbours), i.e. through
     `_bbw_out`, with the EXIT trap silent (`:75-79`).
   - A second case covers a real-spelling path with no rewrite.
   - Both use the canonicalised `FILE` (`:55`).
3. **Timing stated honestly.**
   - The advisory text is worded post-hoc: "You just created X; its nearest existing files are A, B.
     If X restates A, move anything new into A and delete X".
   - Retire the "about to" tense in the same hook's OVERWRITE GUARD (`:248`), which has the same defect.
4. **Outcome check (consumer = the model's next actions).** A nightly pass over the prior day's `fired` rows reports:
   - `kept_distinct`: new file present, and no neighbour mtime after ts;
   - `merged`: new file absent and a neighbour modified after ts;
   - `superseded`: `superseded_by` present;
   - `unresolved`: new file present and a neighbour modified. This is likely a duplicate left behind, so
     report it for compact-memory.
   
   It needs only `stat` and the rows, and is feasible because the store is plain files.
5. **Friction probe.** One session probe records whether `rm <abs memory path>` is auto-allowed, sent
   to the classifier, or prompted under `defaultMode: auto` (§2.8). If it prompts, reword the advice to
   "Edit A, then leave X for compact-memory's orphan sweep", which needs no rm.
6. **Operator option, not adopted here.** A deny-once variant would make the advice arrive **before**
   the write:
   - use `permissionDecision: deny` with the neighbours as the reason, once per (session, canonical path);
   - the second Write passes;
   - the same hook already denies for the index budget (`:125-134`).
   
   Cost: one extra round-trip per new memory file, about 55 per week fleet-wide (ESTIMATED from
   births × Write share), and a risk of suppressing capture. It would be the treatment arm if item 4's
   `unresolved` share stays high.

### #14 transcript-normaliser
1. **Loud fallback.** The import attempt is logged once per process as `norm=lib` or
   `norm=fallback:<ExcType>`, to session-index.log and as an IDL row `session-index:norm`. A fallback
   row is BLIND (`norm-import-failed`, X3). The fallback stays, because the index must not die.
2. **Consumer bats, not only lib bats.**
   - Call `session_index_extract_context` (the bash function, as `hooks/session-index-end.sh:114` calls
     it) on a captured real transcript fixture containing Stop-hook feedback, a skill body, a peer
     message and one typed prompt. Assert the context holds only the typed prompt.
   - Repeat with the lib made unimportable (a temp copy of the helpers without the lib). Assert the
     `norm=fallback` line **and** a non-zero exit from a `--strict` switch used only by tests.
3. **Output metric on the consumer's product.** A nightly share of `sessions.context_text` rows indexed
   in the last 24 h that match the non-operator markers from `fit-tn/leak.py` (Stop hook feedback,
   `Base directory for this skill:`, `Another Claude session sent a message:`).
   - Baseline 64% (78/122, `fit-transcript-normaliser.notes.txt:16`).
   - Accept at ≤ 10% after deploy (threshold ESTIMATED). Page on regression.
4. **Sequencing.** Of the three python blocks, `session_index_extract_all` (`helpers:816`) is fed by
   the sweep, which is dead until #2 P0 (SYNTHESIS:148-152). Its change cannot be observed live before
   #2 lands, so acceptance reads the SessionEnd path only (`session-index-end.sh:99,114`).
5. **Out-of-reach copies.** The sibling repo's `claude-session-search/hooks/lib/session-index-helpers.sh`
   differs from ours (MEASURED `cmp`; last commit 2026-06-17) and will not import the new lib. Record it
   as out of scope so "one Python copy" is not claimed.

### #4 cc-memory-search
1. **One row per invocation**, written in a `finally`, even on crash: `ts, sid (if known), argv hash,
   scope, resolved store realpath, rc, n_hits, top score, elapsed_ms`.
2. **Parity with the independent log.** `cc-memory-search` commands in bash-execution.log(+.gz) against
   tool rows. Surplus Bash invocations mean a crash before logging. `Exit: 127` means the tool is
   unreachable. Both page.
3. **Known-answer canary per active store, nightly.** Query the store's newest topic `name` and expect
   that file in the top 5. It checks the live store and the live scope resolution; #5's frozen snapshot does not.
4. **Zero-hit share** across real invocations is reported. Above 50% (ESTIMATED threshold) is treated as
   probable scope misresolution, not "nothing relevant".
5. **Both CLAUDE variants carry the instruction**: `CLAUDE.global.md:103` **and**
   `CLAUDE.global.slim.md:47` (§2.5). A static check asserts that the tool name appears in both. The
   same fix applies to #10 (`:103-104`), #12 (`:108-109`) and #27 (`:101-104`).

---

## 4. Does this change any disposition in SYNTHESIS.md?

| # | Current | After this gap | Why |
|---|---|---|---|
| 3 | build-now, 78, S | **build-now, 78, S-M.** Scope grows into the expected-fires registry, and it becomes a gate for #6, #10 and #14. | Their liveness depends on it; §2.4 means the nudge denominator must be summed over 4 dirs. |
| 6 | build-now, 72, S | **build-now; conviction 68-70.** Step 5 is re-scoped from "2-week holdout" to "liveness+delivery gate, then an efficacy read at ≥ 15 control events". | §2.7 power; §2.2 event-name and combined-key risks; PostToolUseFailure has 0 live uses. |
| 10 | build-now, 75, S | **build-now, 72-75.** Add the outcome check and post-hoc wording; move the log to `$HOME/.claude/state`; deny-once goes to the operator. | §2.1 (266/266 post-hoc); §2.8 rm friction; §2.4. |
| 14 | build-now, 70, S | **build-now, 70.** The fallback becomes loud, a consumer-level bats test and output metric are added, and the sweep block waits for #2. | §1, §3. |
| 4 | build-now, 78, S-M | **build-now, 78.** Target list adds `CLAUDE.global.slim.md:47`. | §2.5 (about 93% of the last day's transcripts are under slim roots). |
| 7 | build-now, 74, XS | **build-now.** Note that a new `.jq` lib is never linked (§2.3); resolve it through the deref'd path or inline the def. | §2.3 |
| 12, 27 | as is | Target lists add `CLAUDE.global.slim.md`. | §2.5 |

No item flips between build-now, build-later, experiment and reject. The ranked order is unchanged,
except that #3 now precedes #6, #10 and #14, as their acceptance gate, rather than sitting beside them in Wave A.

---

## 5. Receipts (all under `/tmp/tm-research/gap4/`)
- **`order.py`:** position of tool-hook context attachments relative to their tool_use and tool_result
  lines, 4 roots, 2 days (522 files, 8.2 s).
- **`births.py`:** new topic files by birthtime (7, 14, 30 d) per store.
- **`bash7d.log`:** the slice of bash-execution.log used for the Bash-volume and memory-grep counts.
- **`tx1d.txt`:** the last day's transcript list (288 files, 806 MB) used for the offload-marker count.
- **`ctx-sample.txt`:** 400 random recent `context_text` prefixes. Mostly eval-fixture prompts, so it
  is not used as a contamination figure.
- **Static reads:**
  - `_cc_strings.txt:191582,195712,294055,295233`;
  - `_cc_hooks.md:776,1003,1799,2004,2021,2106`;
  - `hooks/bash-output-offload.sh`, `hooks/log-bash.sh`, `hooks/backup-before-write.sh`,
    `hooks/rm-safe-allowlist.sh`, `hooks/lib/idl-log.sh`, `scripts/idl-abstain-alarm.sh`,
    `hooks/lib/session-index-helpers.sh`, `install.sh:334-343`, `scripts/deploy-parity-assert.sh:540-566`,
    `CLAUDE.global.md:103-104`, `CLAUDE.global.slim.md:47`;
  - settings registrations (jq, read-only).
- **Nothing was written** outside `/tmp/tm-research/`. Memory stores, settings and transcripts were read only.
