---
status: open
---

# HOOK_SURFACE_100P — measure the entire Claude Code hook surface, then adopt all of it that earns its cost

**Status:** **W1 DONE — measurement complete. All 31 events on 2.1.220 and all 27 on 2.1.114 carry a
verdict from a command that was RUN, with the command quoted in § 3a and the binary and invocation
mode named in § 3.** W2 (pricing) folded into W1 and also done — both HOLDs are discharged
(`MessageDisplay` § 3 unknown 1, `PostToolBatch` § 3 table). W3 (wire what earns it) NOT started;
W4 (adversarial review of the completed ledger) partially done — see § 3d.
**Origin:** investigating anthropics/claude-code#91870 (Function Hooks) 2026-09-03..05. That proposal
is Anthropic's, pre-decision, and **not on the critical path** — the investigation's real finding is
that we under-use the surface that already ships. Provenance record:
`docs/research/function-hooks-91870-2026-09-03.md` (sha `fbb9d52f1`).

    Scope (frozen): measure every hook event and handler type the installed binaries actually
    dispatch, decide per item whether it earns its cost, and wire everything that does — leaving
    no item in "present in the binary but never probed".

**The standard, stated so it cannot be gamed:** an item is DONE when its row in § 3 carries a
verdict from a command that was RUN, with that command quoted. "Present in `strings`" is not a
verdict — that instrument already produced one false census here (§ 5).

---

## Phase 0 — orchestration (MANDATORY FIRST SECTION)

| Wave | Locus | Why | Model / effort |
|---|---|---|---|
| **W1 · probe the events lacking a verdict** | **S** (dispatched session) — default | 12 events × 2 binaries × 2 invocation modes is breadth-first fan-out; findings, not code | ultracode Workflow, Opus @ high — **DONE 2026-09-05** |
| **W2 · price the two unpriceable events** | **S** | needs an instrumented interactive session + a tool-call census; different rig from W1 | **DONE, folded into W1** — the TUI rig turned out to be one pty run, not a separate wave (§ 3c) |
| **W3 · wire what earns it** | **S**, one session per event group | each wiring is an independent, self-verifiable change to a fleet-wide file | Opus @ high |
| **W4 · adversarial review of the ledger** | **T** (in-session teammates) — justification: the reviewers must be synthesised against each other immediately and their combined output is small | — | Opus @ xhigh |

**Lead context budget:** hold ≥50% of the window for deciding. **Succession point:** recycle at each
wave boundary, or at ~60% fill, whichever comes first (§ 6).

**Shared task list (belt-and-suspenders):** create one list keyed to this plan, one task per § 3 row.
The plan is the SSOT for *findings*; the task list is the SSOT for *what is left*. When they disagree,
the plan wins and the task list gets corrected — never the reverse.

---

## 1. What is settled, and how

| Fact | Method | Where |
|---|---|---|
| Canonical hook events: **27 on 2.1.114, 31 on 2.1.220** | ~~`claude doctor` prints the valid list free~~ — **FALSE, corrected 2026-09-05: doctor prints the install report and no event list at all.** Replaced by each binary's own **contiguous enum literal**, which is a bounded instrument (the block ends at a non-event token, so a 32nd event would be visible): `sed -n '263618,263648p' /tmp/hs/220/strings.txt` → 31 · `grep -oE '"PreToolUse"(,"[A-Za-z]+")+' /tmp/hs/114/strings.txt \| sort -u` → 27 | this plan § 5 |
| The 27/31 count is now **non-circular** | The predecessor derivation was `strings \| grep <list-of-31-names>` — it can only find names you supply, so it could never see a 32nd event. It returned the right number by construction, not by measurement. The enum-literal read above replaces it | § 5 |
| Handler types: **six + the SDK callback**, not four | `command`, `http`, `prompt`, `agent`, **`mcp_tool`**, **`function`**, `callback` — read off the dispatcher switch. A **`function`** handler type, which is what #91870 proposes, ALREADY SHIPS on 2.1.220 | § 3 fifth unknown |
| `prompt`/`agent` support is gated on **`toolUseContext` at the call site**, not on an event list | source read + measured on both binaries: refused on `SessionStart`, accepted on `Stop` and `UserPromptSubmit` | § 3 unknown 4 |
| **`--settings <file>` MERGES with the live settings; it does not replace them** | a probe run's stream carried 8 real fleet `SessionStart` hook_responses. A throwaway `CLAUDE_CONFIG_DIR` DOES isolate totally — but loses auth (`authentication_failed`). **Isolation XOR auth** | § 3a, § 5 |
| An **unknown hook event name is silently accepted** — no error, no warning, no log line | `{"hooks":{"NoSuchEventXYZ":[...]}}` ran normally | § 5 |
| `PreModelSwitch` / `PostModelSwitch` are **not hook events** on either binary | same | — |
| **`PostToolUse` never fires on a failing tool** — the harness dispatches `PostToolUseFailure` instead | positive control in one 2.1.220 run: `echo ok` → PostToolUse; `false` → PostToolUseFailure, no PostToolUse | landed fix |
| No hook payload carries **any** context/token/window field | three independent methods: raw stdin dumped across 16 events, the single shared input-builder function, a scan of all 31 schemas | — |
| `http`, `prompt`, `agent` handler types **work** on 2.1.220 | end-to-end, both allow and block arms | — |
| `prompt` / `agent` are **boolean condition evaluators** returning ok/reason — they cannot emit `additionalContext`, and they **fail OPEN** on evaluator error | same | ⚠ limits the "move judgment out of bash" idea materially |
| **A malformed hook entry silently disables every hook in that settings file**, zero log output | control/test matrix, per-file containment shown | ⚠ see § 4 adoption precondition |
| `WorktreeCreate` is a **provider** hook — a naive exit-0 observer breaks worktree creation | it fired, then `EnterWorktree` failed with "hook succeeded but returned no worktree path" | ⚠ **single-occupancy**, already correctly wired to `worktree-setup.sh` |

## 2. Implementation state

| Item | State |
|---|---|
| `hooks/log-bash.sh` real exit codes | **LANDED** (`2d003a521`, content-verified on trunk). Live layer converges on its own — 13 behind, inside the 25/6h budget |
| `PostToolUseFailure` registration | **WIRED** in `~/.claude/settings.json`, 90 registrations, binary validator accepts |
| `settings-templates/settings.example.json` | carries `PostToolUseFailure`; also already carried `SubagentStop`, which the live file had never picked up |
| `hooks/file-changed.sh` + `tests/file-changed.bats` | **LANDED** (`5ab90b02c`) — handler + 21-test suite. NOT registered; see W3-B below |
| `hooks/instructions-loaded.sh` + `tests/instructions-loaded.bats` | **LANDED** (`5ab90b02c`) — handler + 15-test suite. NOT registered; see W3-B below |
| `hooks/stop-failure-marker.sh` + suite | **LANDED** (`53edbbcf3`, content-verified on trunk — W3-A). NOT registered: no settings file was touched, per § 4 |
| `hooks/subagent-stop.sh` v1 → v2 + suite | **LANDED** (`53edbbcf3`, same commit, content-verified). Still registered NOWHERE — the script was already on disk and unwired before this |
| `hooks/post-tool-batch.sh` + `tests/post-tool-batch.bats` | **LANDED** (`647048376`, content-verified on trunk — W3-C). Handler + 15-test suite, 9-mutant red-proof, 0-red baseline. NOT registered, per § 4 |
| `hooks/permission-denied.sh` + `tests/permission-denied.bats` | **LANDED** (`426d5da66`, content-verified on trunk — W3-D). Handler + 15-test suite. NOT registered; the suite has an arm that FAILS if any settings file in this repo names it |
| `hooks/post-compact.sh` + `tests/post-compact.bats` | **LANDED** (`426d5da66`, same commit — W3-D). Handler + 19-test suite. Records `trigger` + a bounded digest of the ~21.8 KB `compact_summary`, never the body. NOT registered |
| `hooks/config-change.sh` + `tests/config-change.bats` | **LANDED** (`426d5da66`, same commit — W3-D). Handler + 20-test suite. Decision-class: empty stdout on every path. Records whether a changed settings file still PARSES. NOT registered |
| Everything else in § 3 | **measured, not yet adopted** — W1/W2 complete, W3's waves ALL LANDED (**A** `StopFailure`/`SubagentStop`, **B** `FileChanged`/`InstructionsLoaded`, **C** `PostToolBatch`, **D** `PermissionDenied`/`PostCompact`/`ConfigChange`). D was a fourth wave, added after W4 promoted its three rows |
| `migrations/0019-hook-surface-registration.sh` + the § 4 assertion in `hooks/config-mirror-assert.sh` | **WRITTEN and STAGED (c10 — waits for a human), 2026-09-07.** The registration half W3 was missing. Registers `StopFailure`, `InstructionsLoaded` (matcher `session_start`) and `PostToolBatch` across the five fleet config dirs — idempotent, JSON-validated and content-verified before it replaces any file, per-file backup, and it re-asserts that `Stop` and `PreToolUse` survived the edit. Operator ruling `ab82a67e2c37` chose `settings.json` after § 4's separate-file rule was measured unsatisfiable. **Deliberately NOT in it:** `SubagentStop` (migration 0014 already stages exactly this), `FileChanged`+`CwdChanged` (need § 3e's three-part wiring, and `hooks/cwd-changed.sh` does not exist — wiring FileChanged without its re-arm partner yields a watcher that silently empties on the first `cd`, which is worse than not wiring it), and `PermissionDenied`/`PostCompact`/`ConfigChange` (promoted to WIRE by the W4 pass AFTER the W3 waves were briefed, so they had no handlers when 0019 was written — **corrected 2026-09-07: W3-D landed all three (`426d5da66`), so the exclusion now rests on REGISTRATION scope alone, not on their absence. A follow-on migration is the right and only place to wire them; 0019 itself is unchanged**). Gate: `shellcheck` clean · `bash -n` clean · **10/10** related suites green with `RAN==TOTAL` · idempotence guard verified on a sandbox copy (90→91 registrations, `Stop` intact) · the drift assertion carries BOTH controls — silent when whole, names the event when one is removed |

**Net capability change so far: one repair, plus EIGHT handlers written and landed across W3-A, W3-B,
W3-C and W3-D — every one of them NOT YET REGISTERED, and therefore inert.** § 3's other WIRE rows are
still only recommendations. The gap between "landed" and "wired" is deliberate and is closed in
exactly one place: the desk's c10 migration, composed once — and its precondition, all three W3
sessions landed, is now met.

### W3-D — `PermissionDenied` + `PostCompact` + `ConfigChange` (landed `426d5da66`, 2026-09-07)

**Handlers + suites only. Nothing is registered**, per § 4 — same shape as W3-A/B/C. These three
were the ONLY WIRE rows in § 3 with no handler at all: the W4 pass promoted them AFTER the W3-A/B/C
briefs were written, which is why `migrations/0019` names them as deliberately excluded. That
exclusion clause is now stale in one word only — they have handlers; they still have no
registration, and the migration is still the right and only place for one.

**Each suite carries an arm asserting the handler's own name appears in NO settings file in this
repo.** That is the § 4 precondition made mechanical rather than remembered: a future session
cannot wire one of these from inside the wave's own deliverable without going red.

| | `PermissionDenied` → `hooks/permission-denied.sh` | `PostCompact` → `hooks/post-compact.sh` | `ConfigChange` → `hooks/config-change.sh` |
|---|---|---|---|
| What it writes | one JSONL row per DENIAL: tool, `reason`, `tool_use_id`, mode | one bounded row per compaction: `trigger`, summary length + sha256 + 160-char head | one row per config write: `source`, `file_path`, path-derived `kind`, and `json_ok` |
| The constraint that shapes it | `{hookEventName, retry:boolean}` — **`retry:true` RE-OFFERS the denied call** | `compact_summary` measured **21,834** and **5,989** chars — never echo or store stdin whole | **decision-class** — a non-empty stdout freezes config/skill hot-reload for the session |
| How it satisfies it | there is NO writer to stdout anywhere in the file, and the suite asserts empty stdout per payload class | the body is bounded (`.[0:$hc]`) before it can reach the row; the 21,834-char fixture yields a <1 KB log | same: no writer, asserted per class |

**Why no `exec 1>/dev/null` guard, on any of the three.** It was written and then deleted: with no
writer to stdout it is un-falsifiable — no mutant can make it matter — which is exactly the
`type == "array"` dead code the W3-C sweep removed from `post-tool-batch.sh`. Two mechanisms
producing one outcome means no test can credit either. The contract is held instead by per-path
assertions that CAN go red, and a mutant that appends a `retry:true` line to the fired path reddens
three of them.

**The `PermissionDenied` event gate is load-bearing in a way `PostToolBatch`'s was not.** W3-C found
its event gate initially had no arm, because a shape gate refused the fixture first. Here no shape
gate is possible: a `PreToolUse` payload carries `tool_name`, `tool_input` **and** `tool_use_id`, so
it is field-for-field indistinguishable from a denial except by `hook_event_name`. Without the gate,
a mis-registration would record every tool call in the fleet as a refusal — not noisy, but the
opposite of the truth. The `PreToolUse` and `PostToolUse` arms are what pin it.

🚨 **A § 3a CORRECTION, recorded here rather than applied there** (§ 3's rows are not this wave's to
edit). The row-24 writeup gives `ConfigChange`'s `source` as `"local_settings"`. The capture holds
**two** values: `local_settings` for `.claude/settings.local.json` and **`skills`** for
`.claude/commands/hsprobe.md` (both in `/tmp/hs/log/session.tsv`, same run). Nobody has read this
event's value list out of the binary's hook metadata — unlike `InstructionsLoaded`, whose
`matcherMetadata` literal W3-B used as a bounded instrument — so the enum is **unbounded as far as
any of us knows**. The handler therefore classifies on the FILE PATH, which is measured and
self-describing, and records `source` verbatim as data. A tripwire keyed on an unmeasured enum stops
covering its case the first time a value is added, silently. This is the same shape as W3-B's
`load_reason` correction one level down: the writeup was right that `local_settings` occurs and
wrong that it is the whole list, and the correct half lent credibility to the unchecked half.

**`PostCompact`'s case is narrower than it looks, and the header says so.** `SessionStart
source=compact` already fires ~1.3 s earlier and is already wired fleet-wide, so the OCCURRENCE of a
compaction is free today and **counting alone does not justify this hook**. Only the two fields do.
`trigger` is the field `CONTEXT_ECONOMY_V2` derives by scraping transcripts, and its 39/39-manual /
0-auto finding rests entirely on that scraper; an observed field is a different class of evidence.
Both captures read `manual`, so the suite fixtures the `auto` SCHEMA value — a handler hardcoding
`"manual"` would pass every observation made to date.

**What `json_ok` is, and its one false-positive mode.** For a settings file the handler re-reads the
named path and records whether it still parses — the plan's own "one malformed entry silently
disables all 90 registrations with zero log output" hazard, made observable at the moment it
happens. But the hook fires ON the write, so a read can land MID-WRITE on a truncated file that is
valid milliseconds later (memory `peer-worktree-read-midwrite-parses-as-a-code-defect`). So a
FAILING first parse — and only a failing one — is re-checked once after a bounded sleep, and the row
carries `rechecked` so a reader can tell a settled verdict from a single sample. The suite
reproduces that window **deterministically**, with a `jq` stub that fails the first file-parse and
delegates everything else, rather than racing a real writer and shipping a flake.

| | |
|---|---|
| Gate | **54 tests green** (15 + 19 + 20), `RAN == TOTAL` on every suite · `shellcheck` clean · `bash -n` clean · related-suite sweep `14/14 related suites, 271 tests, `RAN == TOTAL == 14`, 0 skips, 0 red (the three new suites, the five sibling hook-surface suites, and the six fleet lints every new `.sh`/`.bats` becomes subject to)` |
| Red-proof | **33 mutants, one per site, 0-red unmutated baseline, every mutant reddened ≥1 named test, 0 sites unproven** |
| Registered | **nothing** — no settings file was touched, and each suite has an arm that fails if one is |

**The 33 sites, and what each mutant killed:**

| Subject | Site | Red |
|---|---|---|
| `permission-denied` | kill-switch · empty-stdin · no-jq abstain · event-name gate · `reason` field · `tool_name` field · `tool_input` truncation · malformed-JSON abstain · rotation · stdout silence | 1 · 2 · 1 · 2 · 2 · 2 · 1 · 1 · 1 · 3 |
| `post-compact` | kill-switch · empty-stdin · no-jq abstain · event-name gate · malformed-JSON abstain · `trigger` field · `summary_chars` · sha-over-whole-body · head truncation · rotation | 1 · 2 · 1 · 2 · 1 · 2 · 3 · 2 · 1 · 1 |
| `config-change` | kill-switch · empty-stdin · no-jq abstain · event-name gate · malformed-JSON abstain · `@sh` emitter · `eval` reader · classify-on-path · parse verdict · absent-file verdict · mid-write re-check · parse size cap · rotation | 1 · 2 · 1 · 1 · 1 · 11 · 10 · 1 · 2 · 1 · 1 · 1 · 1 |

The two `config-change` field-extraction sites are the emitter (`@sh`) and its reader (`eval`), and
they are counted separately because each is independently mutable — but the historical defect they
defend against is only expressible in BOTH halves at once (`@tsv` + `read`, where a tab is IFS
whitespace so an absent leading field shifts every later one LEFT; measured on `hooks/file-changed.sh`,
memory `ifs-whitespace-collapses-empty-fields`). Either half alone is a garbled shape rather than
that bug, which is why each reddens ~half the suite instead of one arm.

**One thing worth carrying forward.** The red-proof harness is a scratch artifact, deliberately not
checked in: `tests/anti-vacuity-contract.bats` globs `tests/*redproof* scripts/*redproof*` and
requires every match to be invoked by a named case there with a `--check-anchors`/`--check-cases`
self-check mode. Landing a fourth-plus harness without that wiring turns that suite red for every
future lander. W3-C recorded its sweep in this section rather than as a file for the same reason;
the shape is the precedent, not an omission.

### W3-C — `PostToolBatch` (landed `647048376`, 2026-09-06)

**Script + tests only; not registered** (§ 4), same shape as W3-A/B. `hooks/post-tool-batch.sh`
writes the ALL-TOOL-CALL CENSUS — one JSONL line per BATCH into `~/.claude/logs/tool-batch-census.jsonl`,
carrying `n` (the batch size, i.e. the per-call chain's amplification for that batch), the tool-name
breakdown, `permission_mode` and `effort`.

**What it discharges.** The original HOLD on this row was `HOOK_CHAIN_COST.md` R-7
(`f6cc5c79885b`): no all-tool-call census exists, so no match-all hook's cost can be stated per-hour
— `bash-execution.log` covers Bash and nothing else. § 3 discharges the HOLD by observing the ratio
is directly measurable; the handler implements the **discharged** version, in which the event IS the
census rather than something that had to wait for one.

**The 114 arm is measured, not assumed.** `"PostToolBatch"` occurs **0×** in the installed 2.1.114
binary and **7×** in 2.1.220, asserted in the suite with the 2.1.220 positive control run FIRST —
without it an absence proves only that the pattern was wrong. Two further binary-independent arms
cover the operational hazard, and they are separate because the two gates producing inertness are
independent: a real `PostToolUse` payload is refused by the SHAPE gate (it has no `tool_calls`),
and a synthetic non-batch payload that DOES carry `tool_calls` is refused by the EVENT-NAME gate.

**Two findings the mutation sweep produced, both real.** (1) The event-name gate initially had no
arm that exercised it — deleting it left the suite green, because the shape gate refused the fixture
first. (2) A `type == "array"` guard was unfalsifiable dead code and was deleted from the subject:
`null|length` is 0, and every non-array surviving `length` makes the following `map` raise, which
empties the row by the same path. Two gates producing one outcome means no test can credit either.
Final sweep: **9 mutants, one per site, 0-red unmutated baseline, every mutant reddened ≥1 test.**

**One thing the land surfaced for the fleet, not just this wave.** The `.bats` shellcheck arm
(`bats-shellcheck-lint`) blocks on SC2181 — `[ "$?" -eq 0 ]` — and this suite was the first `.bats`
file it had ever linted. The fix is bats' `run`/`$status`; the trap on the way there is that piping
a producer into a helper that wraps `run` puts `run` in a SUBSHELL, so `$status` arrives EMPTY and
fails as `[: : integer expected` — a harness error, not a wrong value.

### W3-A — `StopFailure` + `SubagentStop` (landed `53edbbcf3`, 2026-09-06)

**Both are scripts + tests only. Neither is registered, and that is the deliverable's shape, not an
omission** (§ 4): one malformed entry silently disables all 90 registrations in `~/.claude/settings.json`
with zero log output, so the desk composes ONE registration as a c10 migration after all three W3
sessions land. Until it does, both handlers are inert — landed is not wired, and wired is not live.

| | `StopFailure` → `hooks/stop-failure-marker.sh` (new) | `SubagentStop` → `hooks/subagent-stop.sh` (v1 → v2) |
|---|---|---|
| What it does | writes a MARKER keyed on the CAUSE — `error` × account — never on the session | indexes a subagent's report as a POINTER, never a copy |
| The constraint it had to satisfy | ~30 sessions die together on one cap; a page-per-death is 30 pages for one fact | Stop-family: a blocking response extends the turn and increments the harness's block counter (cap 8) |
| How it satisfies it | the collapse is done in the KEY, so N deaths write N lines into ONE file and the operator-visible fact is the file. Paging stays with the reader; the hook notifies nobody | writes NOTHING to stdout on any path, always exits 0 — pinned by test now, not by intent |

**Three findings from doing the work, each of which changed the code:**

1. **The v1 `SubagentStop` hook was quieter than it looked, and had been since it was written.** Its
   header says the schema was undocumented — it was, then. W1 measured it, and v1's guessed chain for
   the report body does not contain `last_assistant_message`, which is the real key. So `FINAL` was
   **always** `""` and every pointer line it ever wrote recorded `final_chars:0`: a harvest index that
   existed, ran, logged a plausible record, and pointed at nothing. This is the same shape as the
   `log-bash.sh` defect W1 already fixed — a real-looking record whose payload-derived field is always
   the default — which makes it a *class* in this repo, not a coincidence. `agent_id` was not read at
   all, and it is the only field that tells two concurrent agents of the same `agent_type` apart.
   Measured keys now lead each chain; v1's guesses stay behind them, so a future rename degrades to a
   wrong-but-present label rather than to blank.
2. **`wc -l < "$f" 2>/dev/null` does not suppress an absent file.** A failed input *redirection* is
   reported by the shell before `wc` ever runs, so the first death of every cause printed to stderr —
   on the death path, which is the one place a stray byte is least affordable. Caught by smoke-testing
   the real payload, not by review.
3. **The land gate caught a defect in this wave's own control, and the catch is the reusable part.**
   The pre-fix control replayed `git show HEAD:hooks/subagent-stop.sh` — a MOVING ref, which becomes
   the *fixed* file the moment the fix lands, so the control would have compared the fix to itself and
   passed vacuously forever. `scripts/moving-ref-control-lint.sh` refused the land (exit 6) and named
   both halves of the fix: pin a LITERAL sha (`8c591f8`, the commit that added v1 and an ancestor of
   trunk), **and** assert a marker the fix introduced is ABSENT from the replay, since the pin alone
   re-goes-vacuous if the sha is ever re-pointed. Markers used (`AGENT_ID`, `last_assistant_message`)
   were derived from the two artifacts' measured diff — 0 occurrences pre, 4 post — not from the
   post-fix file's own explanatory comments, which is the trap the lint's own message warns about.

**Test discipline, so a later session can tell what these suites do and do not prove.** 27 cases, both
suites hermetic (fixtured `$HOME`; `CLAUDE_CONFIG_DIR` unset, since on this box it points at a live
account dir the subject reads to name the account). Payloads are verbatim 2.1.220 captures
(`/tmp/hs/log/{stopfail,sub3}.tsv`) — a suite proving a script works on a payload nobody sends proves
nothing about production. Each suite carries a control that can actually fail, and both were checked
against an emptied subject: **12 and 9 cases go red**, so neither is vacuous.
`CONTROL session_keyed_is_red` mutates the cause-key line to a session-keyed one and requires
"30 deaths ⇒ 1 marker" to go RED (it produces 30); an ANCHOR case asserts that line still exists, so
the control cannot rot into a comment. The collapse is proven under **real 30-way concurrency** — 1
file, 30 lines, 0 bytes of stderr, every line parseable — which is why the marker is append-only
rather than a counter the hook increments: a read-modify-write from 30 concurrent processes loses
writes and needs a lock on the one path where a lock is least affordable.

**What is NOT proven, stated rather than implied:** neither hook has run under a real dispatch, because
neither is registered. Both suites test the handlers against captured payloads; the registration, and
the first live fire, belong to the desk's c10 migration.

### W3-B — `FileChanged` + `InstructionsLoaded` handlers (2026-09-06)

Scripts and suites only. **Nothing is registered**, per § 4: the desk composes ONE registration as a
c10 migration after all three W3 sessions land. Until then both handlers are inert on disk, which is
the intended state and not a loose end.

| | |
|---|---|
| Landed | `5ab90b02c` (handlers + suites) and `3932ae120` (the § 2 record), both ancestors of `origin/main`, content-verified: `git ls-tree origin/main` shows all four paths and `git diff HEAD origin/main -- <paths>` is empty. ⚠️ The pre-land shas were `fdd119751`/`44692e480`. `ship-land.sh` rebases onto the freshest trunk before pushing, so ANY sha written into a doc before the land is rewritten by it — and the stale one still resolves in the author's own checkout, which is what makes the defect invisible to the author and total to everyone else. Cite only post-land shas, each checked with `git merge-base --is-ancestor <sha> origin/main` |
| Gate | 36 tests green · `shellcheck` clean · `bats-shellcheck-lint` clean · `bats-assert-liveness` 0 dead |
| Red-proof | one mutation per site; each killed exactly its own arm (below) |

**🚨 A § 3 CORRECTION, recorded here rather than applied there** (§ 3's ledger rows are not this
wave's to edit). The `InstructionsLoaded consider → WIRE` note gives the five `load_reason` values as
`session_start`, `nested_traversal`, `at_mention`, `skill_load`, `slash_command`. **Three of those do
not exist.** The binary's own hook-metadata literal reads:

    matcherMetadata:{fieldToMatch:"load_reason",
                     values:["session_start","nested_traversal","path_glob_match","include","compact"]}

That is a bounded instrument — the array's brackets end it, so a sixth value would be visible. The
real remaining three are `path_glob_match`, `include`, `compact`. The `fieldToMatch:"load_reason"`
half of § 3's claim is **confirmed** by the same read; only the value list was wrong. Worth noting
for W4: § 3d records that this event's matcher claim was already corrected once by the adversarial
pass ("its matcher being inert" → it is the `load_reason`). The correction was right about the FIELD
and wrong about its VALUES, and nothing re-checked the second half.

**The same read settles `FileChanged`'s matcher mechanism**, which § 3 had only as a measurement:

    "The matcher field specifies filenames to watch in the current directory (e.g. \".envrc|.env\")."
    "Hook output can include hookSpecificOutput.watchPaths (array of absolute paths) to
     dynamically update the watch list."

So the measured absolute-path no-op now has its cause, not just its symptom: an absolute path is not
a filename in cwd, so it cannot match — and the same sentence is why `CwdChanged` is the only re-arm
point. The second line is new to this plan and matters: **`watchPaths` is the supported route to a
path outside cwd**, so the matcher's cwd-locality is a limitation with a documented escape rather
than a hard ceiling. `hooks/file-changed.sh` emits it from an opt-in watchlist file; the default
posture is silent observation, so a registration cannot be surprised by output it did not ask for.

**Matcher recommendations for the desk's migration** (the registration is the desk's call; these are
the values this wave's evidence supports):
- `InstructionsLoaded` → **`session_start`**. It answers the question the event was adopted for and
  is BOUNDED at 2–4 rows/session (all 16 measured rows carry it). `path_glob_match` is the one to
  avoid: it fires per file Claude touches, is unbounded within a session, and answers a different
  question. Rationale for all five is in the handler's header.
- `FileChanged` → **a bare filename or alternation, never a path**. `hooks/file-changed.sh
  --check-matcher <matcher>` exits 1 with the reason on any shape measured or documented never to
  fire, so the migration can assert its own matcher before writing it.

**Two defects the suites caught while being written, both kept as regression arms** — recorded
because each is a shape that passes review:
1. **`run` on the right of a pipe.** bats runs a pipeline's last element in a SUBSHELL, so `$status`
   and `$output` come back empty and every assertion on them passes vacuously. The first draft of
   `tests/file-changed.bats` was green and meaningless. Payloads now reach the hooks by redirection.
2. **The field shift** (memory `ifs-whitespace-collapses-empty-fields`). Both handlers first
   extracted with `@tsv` + `read`; a tab IS an IFS whitespace character, so `read` strips a LEADING
   empty field and shifts every later field left. A payload with no `file_path` logged a row naming
   a file called `change` / `User` rather than skipping it. Both now use `@sh` + `eval`. Notable
   that the citation was already in one handler's comments while the defence was not — a cited
   memory is not an applied one.

**What W3-B does NOT claim.** These files are on trunk, not live: the shared checkout carries
`core.bare=true` (filed `b20eb0842304`), so `~/.claude` cannot converge, and both files are ADDs,
which get no converge budget — an added file is absent rather than stale, so every consumer guard on
it is a silent skip. Expect `🚀`, not `✅`, until an operator clears `core.bare` and the converger
runs.

> **✅ DISCHARGED 2026-09-07 (W3-registration).** `core.bare` was repaired and `deploy-live`
> converged that morning. All FIVE W3 handlers — `stop-failure-marker.sh`, `subagent-stop.sh`,
> `file-changed.sh`, `instructions-loaded.sh`, `post-tool-batch.sh` — are now **live-exec in
> `~/.claude/hooks`** (per-file symlinks into the checkout, re-verified on disk). The paragraph
> above is kept as the historical record of why the `🚀` rung was correct at the time; the
> condition it named no longer holds. What has NOT changed is that landing ≠ registering: measured
> the same morning, `~/.claude/settings.json` carried exactly **90** registrations across 13 event
> keys and `StopFailure` / `PostToolBatch` / `InstructionsLoaded` / `FileChanged` / `CwdChanged`
> were absent from **all five** config dirs. Live-exec and unregistered is still unreachable code
> — it just fails at a different layer than this paragraph predicted.

**What W3 should wire, in descending order of earned value** (each already has its verdict + payload):

1. **`StopFailure`** — fires at the instant of death with `error:"authentication_failed"` and
   `last_assistant_message`. Replaces a 1-hour relogin poll. Must write a MARKER, not a page: 30
   sessions hit one cap together.
2. **`SubagentStop`** — `agent_id` + `agent_transcript_path` + `agent_type`; closes task #192. Must
   stay non-blocking.
   → **Already covered by `migrations/0014-subagent-stop-registration.sh`** (staged, unrun), which
   predates this wave. The 2026-09-07 registration migrations therefore do **not** touch this event:
   0014's append is idempotent only against its OWN command string, so a second migration on the
   same key would create a duplicate row rather than detect one. 0014 remains the single owner.
3. **`FileChanged` + `CwdChanged` as ONE unit** — unblocks tasks #58/#74. 🚨 **Wire it per § 3e, not
   per the obvious reading:** an absolute matcher to ARM, a `*`/no-matcher sibling to DISPATCH, and a
   `CwdChanged` hook re-emitting `watchPaths`. A bare-basename matcher alone silently re-targets on the
   first `cd`; omitting `CwdChanged` empties the watch list entirely.
4. **`PostToolBatch`** — one invocation per batch instead of N, with every `tool_response`. ⚠️ 220-only.
5. **`InstructionsLoaded`** — the only report of which memory files a session actually loaded. Pick the
   `load_reason` matcher deliberately; it is not inert.
6. **`PermissionDenied`** — the ONLY hook that observes a refusal: `PreToolUse` sees the same call and
   cannot see the outcome, and `PostToolUse`/`PostToolUseFailure` never fire on a denial. **105 real
   classifier denials sit in the transcript corpus that no hook of ours has ever seen.** Fires on BOTH
   binaries. ⚠️ Its output schema is `{hookEventName, retry:boolean}` and **`retry:true` re-offers the
   denied call** — the handler must emit EMPTY stdout or it can silently re-drive refused work.
7. **`PostCompact`** — `trigger` (`manual`|`auto`) and `compact_summary` exist nowhere else, and
   `trigger` is exactly the field `CONTEXT_ECONOMY_V2` derives today by scraping transcripts. Note
   `SessionStart source=compact` already fires ~1.3 s earlier, so counting alone does not justify it —
   the fields do. Handler must never echo or store the ~21.8 KB stdin whole.
8. **`ConfigChange`** — the only in-session signal that a settings file changed out-of-band, and it
   names the file: a direct tripwire for this plan's own "one malformed entry silently kills 90
   registrations" hazard. ⚠️ **Decision-class** — the handler must exit 0 with empty stdout or it
   silently freezes config/skill hot-reload for the session.

**Do NOT wire:** `MessageDisplay` (redundant with the transcript, and a `displayContent` return blanks
later text blocks), `WorktreeCreate` / `Elicitation` / `ElicitationResult` (provider- and
decision-class — PROHIBITION), `Setup`, `TaskCreated`, `DirectoryAdded`, `WorktreeRemove`,
`UserPromptExpansion` (`UserPromptSubmit` is already wired fleet-wide and carries the same `prompt_id`
plus the literal `/hsprobe`, so command name and args are already derivable; the only new field is
`command_source`, and it is 220-only — wiring it splits fleet behaviour for one attribution field).

🚨 **A live defect found while measuring, not part of W3 but worth more than most of it.**
`PermissionRequest`'s `tool_use_id` is **always the empty string** — in the live payload captured here
and in **0 of 3,641** archived records. `hooks/cc-permission-beacon.sh` builds its grant-vs-deny
attribution on matching that field, so **that attribution can never succeed and is silently inert
today**; it only looks healthy because resolution falls through to `PostToolUse`'s cleared-tool path.
This is a real bug in a hook we already run fleet-wide, and it is exactly the class the § 5 learning
"a green test can certify a bug" describes. It needs its own fix, separate from any new wiring.

## 3. THE LEDGER — every event, and what it still owes

**Verdict vocabulary — exactly four tokens, and every row carries one:**
`FIRES` (observed, payload captured) · `HOSTILE` (fires, but an observer breaks the host) ·
`DOES-NOT-FIRE` (the dispatcher's real trigger WAS issued, a positive control logged in the same
run, and the hook did not run) · `NOT-APPLICABLE` (the event is absent from that binary's enum, or
structurally unreachable in that mode for a named reason).

Dispositions: **WIRE** · **DROP** · **PROHIBITION** · *wired* (already live in `~/.claude/settings.json`).

> **The two provisional non-verdict states this ledger used to carry are GONE, and deliberately do not
> appear anywhere in this file.** They described the state of *our knowledge*, not of the surface, so
> they could never be discharged by anything except doing the work. Every row below now names the
> binary and the invocation mode that produced it, and every command is quoted in § 3a.
> A row whose trigger could not be issued is not given a verdict on that basis — it is recorded in
> § 3b as owed, with the blocker named. Absence of a trigger is not evidence of absence.

**All 31 events on 2.1.220 and all 27 on 2.1.114 are accounted for below** — the census is re-derived
non-circularly in § 5. `exists` is from each binary's own contiguous enum literal; `measured on` names
the binary and invocation mode that produced the verdict. Commands: § 3a, keyed by event name.

| # | Event | exists 114/220 | Verdict | measured on (binary · mode) | Disposition |
|--:|---|:--:|---|---|---|
| 1 | `PreToolUse` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` | *wired* |
| 2 | `PostToolUse` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` | *wired* |
| 3 | `PostToolUseFailure` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` | **WIRE — done** |
| 4 | `PostToolBatch` | ✗ / ✓ | FIRES (220) · NOT-APPLICABLE (114, absent from enum) | 220 · headless `-p` | **WIRE** |
| 5 | `Notification` | ✓ / ✓ | FIRES | 220 · headless `-p` | *wired* |
| 6 | `UserPromptSubmit` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` | *wired* |
| 7 | `UserPromptExpansion` | ✗ / ✓ | FIRES (220) · NOT-APPLICABLE (114, absent from enum) | 220 · headless `-p` | **DROP** |
| 8 | `SessionStart` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` **and** `--init-only` | *wired* |
| 9 | `SessionEnd` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` **and** `--init-only` | *wired* |
| 10 | `Stop` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` | *wired* |
| 11 | `StopFailure` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p`, unauthenticated | **WIRE** |
| 12 | `SubagentStart` | ✓ / ✓ | FIRES | 220 · headless `-p` | consider |
| 13 | `SubagentStop` | ✓ / ✓ | FIRES | 220 · headless `-p` | **WIRE** |
| 14 | `PreCompact` | ✓ / ✓ | FIRES | 114 · headless `-p` (`/compact`) | *wired* |
| 15 | `PostCompact` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` (`--resume` + `/compact`) | **WIRE** |
| 16 | `PermissionRequest` | ✓ / ✓ | FIRES (interactive) · NOT-APPLICABLE (headless — no dialog without a TTY) | 220 · interactive TUI, production | *wired* |
| 17 | `PermissionDenied` | ✓ / ✓ | FIRES | **114 + 220** · headless `-p`, `--permission-mode auto` | **WIRE** |
| 18 | `Setup` | ✓ / ✓ | FIRES | 114 + 220 · `--init-only` (no model call) | **DROP** |
| 19 | `TeammateIdle` | ✓ / ✓ | FIRES | 220 · interactive, production (27,986 dispatches) | *wired* |
| 20 | `TaskCreated` | ✓ / ✓ | FIRES | 220 · headless `-p` (`TaskCreate` tool) | **DROP** |
| 21 | `TaskCompleted` | ✓ / ✓ | FIRES | 220 · headless `-p` (`TaskUpdate` tool) | *wired* |
| 22 | `Elicitation` | ✓ / ✓ | FIRES | 220 · headless `-p`, purpose-built MCP server | **PROHIBITION** (decision-class) |
| 23 | `ElicitationResult` | ✓ / ✓ | FIRES | 220 · headless `-p`, same run | **PROHIBITION** (decision-class) |
| 24 | `ConfigChange` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` | **WIRE** (decision-class — empty stdout) |
| 25 | `WorktreeCreate` | ✓ / ✓ | **HOSTILE** | 220 · provider contract read + fleet incident | **PROHIBITION** |
| 26 | `WorktreeRemove` | ✓ / ✓ | FIRES | 220 · headless `-p`, `ExitWorktree` in a /tmp repo | **DROP** |
| 27 | `InstructionsLoaded` | ✓ / ✓ | FIRES, and it NAMES the file | 114 + 220 · headless `-p` | **WIRE** |
| 28 | `CwdChanged` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` | **WIRE** — mandatory if 29 is wired |
| 29 | `FileChanged` | ✓ / ✓ | FIRES | 114 + 220 · headless `-p` | **WIRE** — but only as the PAIR in § 3e |
| 30 | `DirectoryAdded` | ✗ / ✓ | FIRES (220) · NOT-APPLICABLE (114, absent from enum) | 220 · headless, `register_repo_root` control request | **DROP** |
| 31 | `MessageDisplay` | ✗ / ✓ | FIRES (220) · NOT-APPLICABLE (114, absent from enum) | 220 · headless `-p` **and** interactive TUI | **DROP** |

**Dispositions that CHANGED against the inherited ledger, and why:**

- **`MessageDisplay` HOLD → DROP.** It is priced now (§ 3c), so the HOLD's blocker is discharged — but
  the reason to drop is **redundancy, not cost**: every byte it delivers is already in the transcript.
  A second reason found in the source makes wiring actively dangerous: a hook returning `displayContent`
  collapses the message to its first text block and **blanks every later text block**.
- **`PostToolBatch` HOLD → WIRE.** Its blocker was "the all-tool-call rate (`f6cc5c79885b`)". That
  backlog item is not needed: the ratio is directly measurable and is **N tool calls ⇒ 1 invocation**
  (measured 3:1). One payload carries every call's `tool_name`, `tool_input` **and** `tool_response`,
  plus `permission_mode` and `effort`, which our PostToolUse payloads lack. ⚠️ 220-only: anything wired
  here is a silent no-op on 114 (§ 5, the silent-acceptance hazard).
- **`InstructionsLoaded` consider → WIRE.** Its condition was "only non-redundant if it names the files
  loaded — unverified". It names them: `file_path` + `memory_type` + `load_reason`. Nothing we own
  reports which memory files a session actually loaded. 🚨 **Its `matcher` is the `load_reason`**, not a
  tool name, and it is NOT inert. ⚠️ **CORRECTED 2026-09-06 — the value list first recorded here was
  wrong in three of five places.** The binary's own hook-metadata literal is the bounded instrument
  (the array's brackets end it, so a sixth value would be visible):

      matcherMetadata:{fieldToMatch:"load_reason",
                       values:["session_start","nested_traversal","path_glob_match","include","compact"]}

  `at_mention`, `skill_load` and `slash_command` **do not exist**; the real remaining three are
  `path_glob_match`, `include`, `compact`. Only two values were exercised, so any per-session rate from
  these logs is a **floor**, not a rate. **Matcher to use: `session_start`** — it answers the question
  the event was adopted for and is bounded at 2–4 rows/session (all 16 measured rows carry it). **The
  one to avoid is `path_glob_match`:** it fires per file Claude touches, is unbounded within a session,
  and answers a different question.

  🚨 **Why this correction is worth more than the fact it fixes.** The `load_reason` finding came from
  the adversarial pass, which was **right about the FIELD** (it is `load_reason`, not a tool name) and
  **wrong about its VALUES** — and the lead propagated both halves because the first half was correct
  and well argued. Nothing re-checked the second half; a sibling W3 session caught it against the
  binary. *A partly-correct correction is harder to catch than a wrong one*, because the verified half
  lends its credibility to the unverified half. Verify a reviewer's claims severally, exactly as § 5
  requires of an instrument.
- **`CwdChanged` DROP → keep.** The inherited reason ("`cwd` is already in all 31 payloads") is true but
  not the point: `FileChanged`'s watch list is resolved **relative to cwd**, so a `cd` silently disarms
  it, and `CwdChanged` is the only re-arm point. Dropping it would quietly break the event above it.
- **`Elicitation` / `ElicitationResult` → PROHIBITION.** Confirmed decision-class: the binary carries
  `decline`, "Elicitation denied by hook" and "Elicitation result blocked by hook". They FIRE, and an
  observer must stay exit-0-with-empty-stdout. Do not wire a decider.
- **`Setup` DROP — confirmed, and now from a run on both binaries** rather than an inference.
  Side-benefit worth reusing: `--init-only` fires Setup + SessionStart + SessionEnd with **no model
  call**, making it the cheapest positive control available to any future probe.

### The four highest-value unknowns — three RESOLVED, one partly

1. **`MessageDisplay`'s real fire rate in an interactive TUI — RESOLVED.** It is neither per-token nor
   per-message: **~1 fire per ~740 displayed characters**, i.e. per paragraph-sized flush. One TUI
   message of 5,942 chars produced **8** invocations, `index` 0→7, `final:true` only on the last.
   Headless `-p` coalesces the whole message into a single delta (a 1,409-byte answer → **1** fire).
   The run really was interactive and that is self-evidencing: `-p` cannot produce index 0..7 with
   seven `final:false` entries. Against the feared "~0.25 cores fleet-wide, ~5× the whole chain",
   the real cost is a handful of invocations per reply. Priced ⇒ the HOLD is discharged; DROP is now
   argued on redundancy (§ 3 table).
2. **Provider-hook semantics — PARTLY RESOLVED, and the remaining part is deliberately unprobed.**
   The contract is readable in the binary and is *per-provider*, not one rule: `WorktreeCreate` fails
   the whole operation if the hook returns no path ("hook succeeded but returned no worktree path"),
   whereas `Elicitation` has its own `decline` / "denied by hook" arm. The N-registered-hooks
   resolution order was **not** settled, because settling it empirically means registering a second
   observer on a live provider — which is the prohibition itself. Read it from source, never by
   experiment on `WorktreeCreate`.
3. **Does anything here reproduce on 2.1.114? — RESOLVED: YES.** Everything tested on both binaries
   agreed: the 7-event core census, `PostToolUseFailure`, `Setup`, `StopFailure`, `FileChanged`,
   `CwdChanged`, `ConfigChange`, `PostCompact`, `InstructionsLoaded`, and the prompt-hook gate.
   No behavioural divergence was found; the only differences are the four events 220 adds.
   🚨 **But see § 5's wording-drift trap — a 114 verdict resting on the ABSENCE of a 220-derived
   string is inadmissible, and that trap fired during this very wave.**
4. **Do `prompt`/`agent` hooks attach to `Stop`/`SessionStart`? — RESOLVED, and both the bundled doc
   and the event-list model are wrong.** The gate is a single source-level condition:

       if (q.type === "prompt") { if (!s) throw Error(`prompt-type hooks are not supported for
         ${p} events (no conversation context is available)...`) }        // s = toolUseContext

   The event name appears only in the *message*; the predicate is whether that event's **call site**
   passes a `toolUseContext`. So support is a property of dispatch, not of a fixed list. Measured on
   both binaries, headless: **refused on `SessionStart`, accepted on `Stop` and `UserPromptSubmit`.**
   Acceptance on `Stop` is proven POSITIVELY, not by absence: a Stop prompt hook given an
   unsatisfiable condition produced **9 Stop fires** — one `stop_hook_active:false` then eight `true`
   — the block loop hitting `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`=8. **The close-integrity idea is
   un-gated on `Stop`.** Its § 1 limits still bind: boolean ok/reason only, no `additionalContext`,
   fails OPEN — so such a hook can refuse a close but cannot feed text back, which is what most of
   our Stop chain does today. Cost caveat: every blocked stop is a model turn **plus** a hook model
   call, so a mis-specified condition burns 8 turns before the cap catches it.

### A fifth unknown, not previously on the board: the handler-type surface is bigger than the plan knew

The dispatcher switches on **six** handler types plus the SDK callback: `command`, `http`, `prompt`,
`agent`, **`mcp_tool`**, **`function`**, `callback`. Two were absent from this plan entirely:

- **`function`** — carries "Messages not provided for function hook". anthropics/claude-code#91870
  proposes "Function Hooks"; **a handler type of that name already ships in 2.1.220.** Whether it is
  the same construct is unestablished, but this plan's framing of #91870 as purely prospective needs
  re-reading against it. This is the single most consequential thing the investigation turned up.
- **`mcp_tool`** — a hook can call an MCP tool directly ("mcp_tool hooks are not available for the
  '<event>' hook event (no MCP client context)"). 220-only by string evidence, which per § 5's
  wording-drift trap is suggestive rather than conclusive.

## 3a. THE COMMANDS — one per § 3 row, all actually run on 2026-09-05/06

Shared rig. `V220=~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe` ·
`V114=~/.claude-versions/2.1.114/node_modules/@anthropic-ai/claude-code/bin/claude.exe`.
Every settings file registers `/tmp/hs/log-event.sh <Event> <tag>` — reads stdin, appends one TSV row
(timestamp, tag, event, full payload) to `/tmp/hs/log/<tag>.tsv`, prints NOTHING, exits 0. Every run
below carries a positive control on an event known to fire, in the SAME run.

**Rows 1,2,6,8,9,10,27 — the core census (one invocation, nine events), and its 114 twin:**

    cd /tmp/hs/scratch && $V220 --settings /tmp/hs/census.json --output-format stream-json --verbose \
      -p 'Run exactly this bash command: echo hello-census. Then reply with the single word done.' < /dev/null
    cd /tmp/hs/scratch && $V114 --settings /tmp/hs/census114.json \
      -p 'Run exactly this bash command: echo hello-114. Then reply with the single word done.' < /dev/null
    cut -f3 /tmp/hs/log/census.tsv | sort | uniq -c        # and census114.tsv

220 → InstructionsLoaded×2 · UserPromptSubmit · Stop · SessionStart · SessionEnd · PreToolUse ·
PostToolUse · PostToolBatch · MessageDisplay. 114 → the same minus PostToolBatch and MessageDisplay.

**Row 3 `PostToolUseFailure`** (220; the 114 arm rode the § 3a batched 114 run):

    cd /tmp/hs/scratch && $V220 --settings /tmp/hs/ptuf.json --allowedTools Bash \
      -p 'Use the Bash tool to run exactly this command: exit 7    Then reply done.' < /dev/null

**Row 4 `PostToolBatch` — the N:1 ratio:**

    cd /tmp/hs/scratch && $V220 --settings /tmp/hs/batch.json \
      -p 'Run these three bash commands in a SINGLE message, in parallel: (1) echo alpha (2) echo beta
          (3) echo gamma. Then reply done.' < /dev/null
    # → 3 PreToolUse · 3 PostToolUse · 1 PostToolBatch, whose tool_calls[] held all three

**Rows 5,22,23 `Notification` / `Elicitation` / `ElicitationResult`** — needed a purpose-built MCP
server, because no shipped server elicits on demand:

    $V220 -p 'Call the tool mcp__elicitprobe__ask_probe exactly once with no arguments, then reply DONE.' \
      --mcp-config /tmp/hs/mcp.json --strict-mcp-config --settings /tmp/hs/settings-elicit.json \
      --allowedTools 'mcp__elicitprobe__ask_probe' --max-turns 4

**Rows 7,24 `UserPromptExpansion` / `ConfigChange`** — one run, two triggers; a background writer
touches a settings file and a slash-command file while a slash command expands:

    ( sleep 8; printf '{"env":{"HS_PROBE":"1"}}\n' > <repo>/.claude/settings.local.json;
      sleep 7; printf '\n<!-- probe touch -->\n' >> <repo>/.claude/commands/hsprobe.md ) &
    $V220 --settings /tmp/hs/settings-run1.json --session-id 11111111-2222-4333-8444-555555555555 \
      --debug-file /tmp/hs/run1.debug -p '/hsprobe'

**Rows 14,15 `PreCompact` / `PostCompact`** — resume the session above and force a real compaction:

    $V220 --settings /tmp/hs/settings-run1.json --resume 11111111-2222-4333-8444-555555555555 \
      --debug-file /tmp/hs/run2.debug -p '/compact'

**Rows 11 `StopFailure` + 8,9,18 `Setup`/SessionStart/SessionEnd — both ZERO-QUOTA:**

    # StopFailure: an unauthenticated throwaway config dir fails auth deterministically
    mkdir -p /tmp/hs/cfg-noauth   # settings.json written INSIDE it
    cd /tmp/hs/scratch && CLAUDE_CONFIG_DIR=/tmp/hs/cfg-noauth $V220 -p 'say pong' < /dev/null
    # Setup: fires with no model call at all
    cd /tmp/hs/scratch && $V220 --settings /tmp/hs/setup.json --init-only < /dev/null

**Rows 12,13 `SubagentStart`/`SubagentStop` and 20,21 `TaskCreated`/`TaskCompleted`:**

    $V220 --settings /tmp/hs/sub3.json -p 'Spawn exactly one subagent with the Agent tool
      (subagent_type: general-purpose, description: ping) whose entire task is to reply with the single
      word ping. Wait for its result, then reply done.' < /dev/null
    $V220 --settings /tmp/hs/task1.json --allowedTools TaskCreate,TaskUpdate,TaskList \
      -p 'Use the TaskCreate tool to create one task titled "hookprobe task". Then use TaskUpdate to set
          it to completed. Then reply done.' < /dev/null

**Row 17 `PermissionDenied`** — needs a denial from the **auto-mode classifier**, not the rule engine:

    cd /tmp/hs/permwork && $V220 --setting-sources project --settings /tmp/hs/perm-settings.json \
      --permission-mode auto -p 'Run exactly these two Bash tool calls, in order, one at a time. If the
      second is denied, do not retry it.  1) echo CONTROL-OK  2) git remote add probeorigin
      https://example.com/probe.git   Then reply with the single word FINISHED.' < /dev/null

**Row 16 `PermissionRequest`** — production evidence, interactive only:

    python3 -c "import json;print(len(json.load(open('$HOME/.claude/settings.json'))['hooks']['PermissionRequest']))"  # 4
    ls ~/.claude/autonomy/permission-archive/ | wc -l    # 3094 archived payloads, 504 distinct 2.1.220 sessions

**Row 19 `TeammateIdle`** — production evidence from the hook's own log (it is registered on this
event and nothing else, so every row is a dispatch):

    wc -l ~/.claude/logs/teammate-lifecycle.log    # 27986, first 2026-04-03, latest 2026-09-05 19:49

**Rows 28,29 `CwdChanged` / `FileChanged`**, plus the matcher A/B that proves the trap:

    cd /tmp/hs/fc && $V220 --print --settings /tmp/hs/fs-settings.json --allowedTools Bash \
      'Use the Bash tool exactly once to run this exact command, then reply DONE. The command is:
       printf x >> /tmp/hs/fc/probe.txt; sleep 9; cd /tmp/hs/cwdtarget; pwd' < /dev/null

Three simultaneous `FileChanged` registrations, one run, three files touched:
`/private/tmp/hs/fc/abs.txt` (ABSOLUTE) → **0 rows** · `*` → **3 rows** · `probe.txt` (bare basename)
→ **1 row**. The absolute-path matcher is a **silent no-op**, measured rather than inferred.

**Row 30 `DirectoryAdded`** — the trigger is a `register_repo_root` control request, not `--add-dir`:

    cd /tmp/hs && /tmp/hs/da-stdin.sh | $V220 --print --input-format stream-json \
      --output-format stream-json --verbose --settings /tmp/hs/da-settings.json

**Row 26 `WorktreeRemove`** — in a THROWAWAY /tmp repo, never the shared checkout:

    git -C /tmp/hs/wtrepo init -q . && git -C /tmp/hs/wtrepo commit --allow-empty -qm init
    cd /tmp/hs/wtrepo && $V220 --settings /tmp/hs/wtr.json --allowedTools EnterWorktree,ExitWorktree,Bash \
      -p 'Use the EnterWorktree tool to create a worktree named probewt, then immediately use
          ExitWorktree to remove it. Then reply done.' < /dev/null
    # payload: {"hook_event_name":"WorktreeRemove","worktree_path":"..."} — observer-class

🚨 **That run cost the fleet an incident, and the cause is worth more than the row.** `--settings`
MERGES (§ 5), so the probe inherited the live `WorktreeCreate` → `hooks/worktree-setup.sh`
registration, whose line 189 is `git -C "$REPO" worktree add`. The shared checkout
`~/Development/claude-infrastructure` was left with **`core.bare=true`** (`is-inside-work-tree=false`),
the exact condition memory `worktree-ops-can-bare-the-shared-checkout` records. Files all remained on
disk and the deploy lane was still waiting on a green tree, so nothing had broken yet — but
`deploy-live.sh`'s `checkout-not-a-worktree` arm would have fired at the next fast-forward. Repair is
that script's own prescription at line 554, filed as backlog `d49917bc4e9e`:
`git -C <repo> config --unset core.bare`. **Lesson for every future probe: a throwaway /tmp subject is
NOT isolation while `--settings` is the rig — the live provider hooks still run, against the real repo.**

**Row 25 `WorktreeCreate`** — HOSTILE, and deliberately NOT re-probed. Verdict stands on the provider
contract read out of the binary ("hook succeeded but returned no worktree path") plus the original
incident. Registering a second observer is the prohibition; the row is closed by reading, not running.

## 3b. What remains owed — named, with the blocker, and NOT counted as a verdict

Nothing in § 3 is missing a verdict. These are *additional* columns that would strengthen rows already
decided; none of them can change a disposition:

| Owed | Blocker | Why it is not a verdict question |
|---|---|---|
| `SubagentStart`/`SubagentStop` on **114** | `agent-teams-enforce.sh` refused the spawn (capacity 11 mid-turn > ceiling 8) — this session's own 15-agent wave was the load | Event exists in 114's enum; 220 FIRES. Retry on a quiet box; do NOT set `CC_ADMIT_GATE=off` while a wave is live |
| `TaskCreated`/`TaskCompleted` on **114** | **there is no `TaskCreate` tool on 2.1.114** — the session fell back to `TodoWrite`, a different mechanism | The events are in 114's enum but the tool that raises them does not ship there. Do not record NOT-APPLICABLE without finding another route |
| `PermissionRequest` on **114**, and `PermissionDenied` on **114** | not probed | 220 verdicts are firm; 114 needs its own run per § 5's wording-drift trap |
| `MessageDisplay` TUI rate on a SECOND sample | n=1 interactive message | The disposition is DROP on redundancy, so the rate no longer gates anything |
| Provider N-hook resolution order | settling it means registering a second observer on a live provider | That is the prohibition itself — read it from source |

## 3e. 🚨 `FileChanged` + `CwdChanged` are ONE wiring, and the obvious prescription is BACKWARDS

**This section exists because the first version of this ledger shipped the wrong instruction.** It
said "the matcher must be a bare relative path; absolute → 0 rows". The dispatch half of that is true
and the *advice* derived from it is inverted. Refuted by an independent verifier that reproduced the
original result twice and then ran the A/B that breaks it.

**Two different mechanisms, and the naive reading collapses them:**

| | ARMING (does the watcher watch this path?) | DISPATCH (does the hook run?) |
|---|---|---|
| absolute matcher | **works, and survives a `cd`** — `isAbsolute(x)?x:join(t,x)` passes absolutes through untouched | **never fires** — the matcher is regex-tested against a bare BASENAME, so an absolute path cannot match |
| bare basename | armed relative to the CURRENT cwd | fires — but see below |
| `*` / no matcher | — | fires for every watched path |

**The trap:** a `cd` inside any Bash tool call **wipes the dynamic watch list and re-bases every
RELATIVE matcher onto the new cwd.** So a bare-basename registration silently stops watching the file
it was wired for and starts watching a same-named file somewhere else. Measured: after a `cd`, the
`probe3.txt` matcher fired for `/private/tmp/hs/fc3/sub/probe3.txt` — a *different file* — while the
originally-armed `dyn.txt` produced **zero** rows.

**Therefore the correct wiring is a PAIR plus a re-arm, and none of the three parts is optional:**

1. an **absolute-path** matcher registration — to ARM the watch durably across `cd`;
2. a **`*` / no-matcher** sibling registration — to actually DISPATCH;
3. a **`CwdChanged`** hook that re-emits `watchPaths` — because `onCwdChanged` **overwrites** the
   dynamic list wholesale with whatever the CwdChanged hooks return (`r = A.watchPaths`). With no
   CwdChanged registration that list becomes **empty on the first `cd`**, and every dynamically-armed
   path is lost silently.

**So `CwdChanged` cannot be DROPped while `FileChanged` is wired — they are mutually dependent, and
the inherited ledger's dispositions (WIRE FileChanged, DROP CwdChanged) were incompatible with each
other without noticing.** Source: `Mf8`/`oC5` (matcher filter, 114:140260 and 220:430421) and
`HJ1()`/`Sx_()` (the wipe-and-rebuild, 114:135528 and 220:171001+).

**The CAUSE behind the measurement, from the binary's own hook documentation** (found by the W3-B
session; § 2 carries the full quote). The matcher field "specifies filenames to watch **in the current
directory**" — so an absolute path is not a filename in cwd and cannot match, which is why the
measured absolute-matcher no-op happens and why `CwdChanged` is the only re-arm point. The second
documented sentence is the part that changes the design: hook output may carry
`hookSpecificOutput.watchPaths`, an **array of absolute paths**, to update the watch list dynamically.
**So cwd-locality is a limitation with a supported escape, not a hard ceiling** — `watchPaths` is the
sanctioned way to watch outside cwd, and it is what makes the three-part wiring above a documented
pattern rather than a workaround. The landed `hooks/file-changed.sh` emits it from an opt-in watchlist
file, defaulting to silent observation so a registration cannot be surprised by output it did not
ask for.

### 3e-FINDING (2026-09-07, W3-registration) — part 3 had NO WORKING IMPLEMENTATION, and its registration would have read GREEN

**The three parts above are a specification, and one of them was unimplemented in the handler that
was supposed to satisfy it.** `hooks/file-changed.sh` guarded on `file_path` with an early
`exit 0` (`:138`) sitting **ABOVE** the `watchPaths` emit (`:153-158`). A `CwdChanged` payload
carries no `file_path` — so the guard fired first and the handler emitted **nothing** on precisely
the event part 3 exists for. Measured on both arms with `CC_FILECHANGED_WATCHLIST` set:

    CwdChanged payload  → stdout EMPTY                                    (cannot re-arm)
    FileChanged payload → {"hookSpecificOutput":{"hookEventName":"FileChanged","watchPaths":[…]}}

**Why this is worth a finding rather than a bug line.** Every sensor available to a registration
would have called it healthy. The command string is in `settings.json` either way; the hook is
executable; it exits 0; the FileChanged arm emits correctly. The failure is visible only by
feeding the handler the *other* event it is registered on — which is a test nobody writes unless
the two-event registration is already understood as ONE unit. It is the § 5 shape ("a green test
can certify a bug") applied to a registration instead of a test: **a registered no-op reads GREEN,
and part 3's no-op would have been silent in exactly the way the empty watch list it was meant to
prevent is silent.**

**THIS IS WHY THE REGISTRATION SPLITS INTO TWO MIGRATIONS** rather than the single one § 2
anticipated:
- `migrations/0016-w3-hook-registration.sh` — the three READY events (`StopFailure`,
  `PostToolBatch`, `InstructionsLoaded`/`session_start`), which needed no handler change.
- `migrations/0017-filechanged-cwdchanged-registration.sh` — `FileChanged` + `CwdChanged` as the
  one three-part unit, staged only AFTER the handler fix, and asserting its own matchers through
  `hooks/file-changed.sh --check-matcher <m> [--role arm]` before it writes them.

**The fix, and the direction it must not overshoot in.** The guard is now scoped to the LOGGING
path alone: a `CwdChanged` payload still writes **no log row** (it names no file, so no later query
could attribute one) but it **does** re-arm. `hookEventName` is read from the payload rather than
hard-coded, so a re-arm is labelled with the event that actually fired it.
`tests/file-changed.bats` pins both directions (arms 26-29).

**A second defect fell out of writing 0017, and it is the more transferable one.**
`--check-matcher` splits its argument on `|` with an **unquoted** expansion, which is also subject
to **pathname expansion** — so the single most important matcher it judges, `*`, globbed to the
caller's cwd and the checker judged 36 filenames instead. It still exited 0, because bare basenames
are accepted, **so the suite's own "the star matcher is ACCEPTED" arm had been passing for entirely
the wrong reason and could never have rejected a bad `*`.** Found only because 0017 asserts its own
dispatch matcher and printed 36 NOTICE lines naming this repo's files. Fixed with `set -f` around
the split; pinned by arm 30. *Generalisable: a checker that must not glob is one unquoted expansion
away from checking something else entirely, and it fails in the passing direction.*

One over-generalisation also did not survive: the hazard "new_cwd can permanently misname the
session's directory" is conditional on the REVERT path, i.e. an out-of-scope `cd`. An in-scope `cd`
into a strict subdirectory was measured with no revert at all — `new_cwd` was accurate and the session
genuinely followed.

## 3c. Both HOLDs are discharged — the two numbers that were missing

| | measured | consequence |
|---|---|---|
| `MessageDisplay`, headless `-p` | **1 fire per assistant message, any length** (1,409-byte answer → 1 fire) | the message is coalesced into a single delta at `index:0` |
| `MessageDisplay`, interactive TUI | **8 fires for a 5,942-char message ⇒ ~1 per ~740 chars** | per paragraph-sized flush; `index` 0→7, `final:true` only on the last |
| `PostToolBatch` | **N tool calls ⇒ 1 invocation** (measured 3:1; 1:1 on a single-tool turn) | strictly cheaper than the per-tool chain, and the payload carries each call's `tool_response` |

The `MessageDisplay` figure sits far below the feared per-token dispatch, and the binary's own
`suppressPerInvocationTelemetry` field exists because this cadence was anticipated. Refinements found
while attacking the figure, all of which strengthen rather than weaken it: the 10 s timeout is
**caller-side** (both call sites pass it explicitly; the dispatcher default is 600 s), and over-cap
flushes are **coalesced, not dropped** (`if(d.inFlight>=lbm)return` skips the dispatch without
advancing `flushedOffset`), so the realized rate is BELOW the ceiling and the cost figure is
conservative.

## 3d. W4 adversarial review — what was attacked, and the honest gap

Three of five event groups were adversarially verified by an independent agent that re-counted the log
rows itself rather than trusting reported counts, re-derived every quoted binary constant with its own
greps, and re-ran at least one probe. **Outcome: no FIRES verdict was refuted.** What did NOT survive
was three *prescriptions* — `FileChanged`'s wiring advice (backwards), `CwdChanged`'s DROP (it is
FileChanged's only re-arm point), and `InstructionsLoaded`'s matcher being inert (it is the
`load_reason`, and it selects which loads you observe). All three corrections are folded into § 3.

⚠️ **CORRECTED 2026-09-06 — an earlier revision of this section was wrong about its own scope.** It
said the workflow "died after 8 of 15 returns" and that THREE groups lacked refutation. The run had
not died; it was still executing and completed later (13 agents, 11 returned, **2 stalled**). The
lead read a zero-process snapshot as death — the same absence-is-not-evidence error this plan is
about, made about its own instrument. What is actually true:

- **`fs`, `display` and `session` DID get an independent refutation pass**, and it changed the ledger
  (§ 3e, and the disposition list above).
- **`permission` and `provider` are the two that stalled** (their `pipeline[0]`/`pipeline[1]` agents
  made no progress across all 6 attempts). Those two groups — `PermissionRequest`, `PermissionDenied`,
  `Elicitation`, `ElicitationResult`, `WorktreeRemove` — have **no adversarial pass**.

Their measurements survive because they are *data, not prose*: the raw payload logs under
`/tmp/hs/log/*.tsv` outlived the agents, and **every verdict from those groups in § 3 was read by the
lead directly out of those payloads**, not taken from an agent's summary. Two checks were run in place
of the missing refuters:

1. **Fabrication check.** Three payloads carried hand-shaped session ids
   (`11111111-2222-…`, `33333333-4444-…`), which is what a synthesized payload would look like. They
   are genuine: each is accompanied by a `SessionStart` row from the SAME id with a real transcript at
   the harness's canonical path, which a hand-invoked hook cannot produce, and the `PostCompact`
   payload carries a real model-written `compact_summary`. The agents had simply passed `--session-id`
   to make their rows findable.
2. **Command recovery.** The three dead agents never wrote their prose files, so their commands were
   recovered from their own transcripts and are quoted verbatim in § 3a.

**W4 is therefore NOT complete.** A successor should run the refutation pass for those three groups
against `/tmp/hs/log/*.tsv` (and re-run the triggers, which are all in § 3a) before this ledger is
called reviewed. It should not need to re-measure anything.

## 4. Adoption preconditions (non-negotiable)

- **Experimental events go in a SEPARATE settings file**, never `~/.claude/settings.json`. One malformed
  entry silently disables all 90 registrations there, including every fact-bound Stop gate and the land
  gate, with no log line.
  🚨 **MEASURED 2026-09-07: this precondition is NOT SATISFIABLE AS WRITTEN, and that is why nothing is
  registered yet.** The obvious separate file — the user config dir's `settings.local.json` — **is not
  read as a hook source.** Two zero-quota `--init-only` runs, each with an in-run control:
  control `settings.json` → 1 row, target user-level `settings.local.json` → **0 rows**; a second run
  adding the project level gave `<cfgdir>/settings.json` → 1, `<project>/.claude/settings.json` → 1,
  `<project>/.claude/settings.local.json` → 1. So hooks load from a PROJECT's settings files but not
  from the user-level local one. Registering there would yield a hook that is registered and never
  fires — **precisely the silent no-op of § 5's unknown-event-name hazard**, and indistinguishable
  from success. The five ready handlers are fleet-wide consumers, so a project-scoped file cannot
  carry them. **Decision filed: `ab82a67e2c37`** (settings.json + count assertion · project-local ·
  launcher `--settings`), default = HOLD, handlers stay inert on disk, which is safe.
- **Assert the expected registration count at SessionStart** — `hooks/config-mirror-assert.sh` is the
  natural home.
- **Never wire an event whose `hookSpecificOutput` schema you have not read.** `WorktreeCreate` is the
  proof; `PermissionRequest` and `Elicitation` are the same class.
- **Probe in a throwaway `CLAUDE_CONFIG_DIR`**, reached only via env prefix; use `--settings` when the
  probe needs real auth.

## 5. Learnings that outlive this plan

- **A green test can certify a bug.** `tests/bash-audit-attrib.bats` synthesises `tool_response.exitCode`
  — a field the harness never sends. It was green for months while all 37,319 logged exit codes read `0`.
  That is *why* nobody looked. The fixture is kept (the contract is worth defending) but now carries a
  header saying it is hypothetical.
- **`strings` produced a false census.** A 6-character length floor hid `Stop` and `Setup`, and it landed
  on 27 by coincidence — right number, wrong derivation. Use the binary's own event enum, or `claude doctor`.
- **"Did not fire" ≠ "does not fire".** Four of five original MEASURED-FALSE verdicts were wrong-trigger
  false negatives. Read the dispatcher's trigger before spending a probe.
- **A sweep must refuse rather than pass vacuously.** Two sweep runs reported ALL-GREEN having executed
  one suite and zero suites (`bats` eats loop stdin; the Bash tool is zsh, so no `mapfile`). The sweep now
  asserts `RAN == TOTAL` and a discovery floor.
- **`git worktree` on the shared checkout can set `core.bare=true`**, killing `deploy-live` fleet-wide
  while every file stays on disk. Memory: `worktree-ops-can-bare-the-shared-checkout`; backlog `693ee60c0885`.
  **It happened AGAIN during W1** (2026-09-05, backlog `d49917bc4e9e`) and the new part is the delivery
  mechanism: the probe's subject was a throwaway `/tmp` repo, but the rig was `--settings`, which MERGES —
  so the fleet's own live `WorktreeCreate` provider ran `git -C "$REPO" worktree add` against the REAL
  repo. **A throwaway subject is not isolation while the rig is `--settings`.**

### Learnings added by W1 (2026-09-05/06)

- 🚨 **A version's WORDING drifts even when its BEHAVIOUR does not — so an absence-of-string check
  across binaries can only manufacture false negatives.** Grepping both dumps for 220's
  `prompt-type hooks are not supported` returned `114=0, 220=2`, one step from "114 has no such guard".
  114 has the guard; it says **`ToolUseContext is required for prompt hooks. This is a bug.`** Same
  predicate, older phrasing (an internal-invariant message later reworded for users). **Any 114 verdict
  resting on the absence of a 220-derived string is inadmissible.** This is the same failure class § 5
  already records for wrong triggers, relocated from the trigger to the *instrument*.
- 🚨 **A probe that parses only JSON and skips parse failures silently discards verdicts.** Hook
  refusals arrive on **three different messages across two channels** — two as `hook_response` JSON with
  `outcome:"error"`, and one (`Prompt stop hooks are not yet supported outside REPL`) as **plain stdout,
  not JSON at all**. A `try: json.loads(l) except: continue` loop drops that third one on the floor.
  Count non-JSON lines and print them; never `except: continue`.
- **`--debug` emits NOTHING under `-p`.** A "0 hits" reading off that output is vacuous — the instrument
  produced no stream. `--output-format stream-json --verbose` is the working instrument. Recorded so it
  is not retried.
- **A hook that prints nothing produces NO `hook_response` record.** Only stdout-producing hooks and
  errors are recorded, so `hook_response` absence is not evidence a hook did not run — and any census
  built on counting those records will silently under-count every silent observer we own.
- **Prefer the ZERO-QUOTA triggers.** Two were found and both work on both binaries: `--init-only`
  (fires Setup + SessionStart + SessionEnd with no model call) and an unauthenticated throwaway
  `CLAUDE_CONFIG_DIR` (fires StopFailure deterministically). Between them they are the cheapest positive
  control available to any future probe.
- **Check the deny rules before choosing a "surely denied" command.** A `PermissionDenied` probe using
  `sudo -n true` measured the **rule engine**, not the classifier — `~/.claude/settings.json` carries 41
  `permissions.deny` rules including `Bash(sudo:*)`, and `--settings` cannot switch them off. The run
  was INCONCLUSIVE, not a refutation. The trigger that works is one no rule covers
  (`git remote add ... https://example.com/probe.git`).
- **Do not let a ledger's evidence be a command shaped like an attack.** The designed
  `PermissionDenied` trigger was the cloud instance-metadata credentials endpoint, chosen precisely
  because it reads as credential exfiltration. It is inert on this laptop, but an inert substitute costs
  nothing and a stored command outlives its context.
- **`validate-bash.sh` matched a dangerous *spelling inside documentation prose*** and refused a heredoc
  that was writing this very section. Data in a heredoc is not code, but the arm text-matches the whole
  command string. Cosmetic here, and deliberately NOT "fixed" — widening or narrowing that arm is what
  memory `denylist-enumerates-spellings-not-the-class` warns against. Work around it with the Write tool.
- **The FileChanged absolute-path matcher never DISPATCHES** — measured by a three-way A/B in ONE run
  (absolute → 0 rows, `*` → 3, bare basename → 1), not inferred. ⚠️ **But do not derive the obvious
  prescription from it, which is what this plan did and shipped.** Arming and dispatch are different
  mechanisms: the absolute matcher is the only `cd`-durable way to ARM, while a bare basename is
  silently RE-BASED onto the new cwd and starts watching a different file. The correct wiring is a
  pair plus a `CwdChanged` re-arm — § 3e. **The generalizable half: when one field feeds two
  mechanisms, an A/B that measures only the second yields advice that is confidently backwards.**
- 🚨 **A PARTLY-CORRECT correction is harder to catch than a wrong one — verify a reviewer severally.**
  The adversarial pass's `InstructionsLoaded` finding had two halves: the matcher is `load_reason` (not
  a tool name), and its five values are `session_start, nested_traversal, at_mention, skill_load,
  slash_command`. The first half was right and well argued; **three of the five values do not exist**
  (the real ones are `path_glob_match`, `include`, `compact`). The lead folded in both halves because
  the verified half lent its credibility to the unverified one, and it took a sibling session reading
  the binary's own `matcherMetadata` literal to catch it. § 5 already demands that an *instrument* be
  controlled; this is the same demand applied to a **reviewer**. Check each claim against its own
  evidence, not against the reviewer's batting average.
- 🚨 **A zero-process snapshot is not death, and I made that error about my own instrument.** The
  15-agent workflow was declared dead after a `ps` showed no `claude.exe` and its agent files had been
  idle 16–33 minutes. It was still running; it completed later and its refutation overturned two
  dispositions in this very ledger (§ 3e). Idleness is not termination, and the harness's own
  completion notification is the only authority on whether a run finished. This is the same
  absence-is-not-evidence failure the whole plan documents, committed by the plan's own author against
  the tool measuring it — which is why it is recorded here rather than quietly fixed.

## 6. Self-management protocol for the driving session

1. **Recycle proactively at wave boundaries or ~60% context fill**, whichever comes first — never ride to
   the wall. `handoff-fire.sh --recycle --goal '<end state> — proven by <check>; do not <constraint>'`.
   A goal dies with its session, so **every recycle re-arms one**.
2. **Update this plan BEFORE recycling.** The successor inherits the plan, not the context. A ledger row
   without its command quoted is not a finding.
3. **Never widen a verdict beyond its population.** Every row states which binary and which invocation
   mode produced it.
4. **Run the full related-suite sweep before every land** — the first attempt at the exit-code fix was
   auto-reverted for skipping exactly this.

## Status log

- **2026-09-06 (later)** — **W4 partially landed, and it overturned two of this ledger's own
  dispositions.** The workflow declared dead in the entry below had not died; it completed (13 agents,
  11 returned, 2 stalled) and its refutation pass arrived afterwards. Corrections applied:
  **`FileChanged`'s wiring prescription was BACKWARDS and is rewritten as § 3e** (arming and dispatch
  are different mechanisms; the fix is an absolute matcher + a `*` sibling + a `CwdChanged` re-arm);
  **`CwdChanged` DROP → WIRE**, since `onCwdChanged` overwrites the watch list wholesale and is the
  only re-arm point, making the inherited pair of dispositions self-contradictory; **`PermissionDenied`
  also FIRES on 114** and rises to WIRE (the only observer of a refusal — 105 classifier denials in the
  corpus no hook has seen; `retry:true` in its output schema makes empty stdout mandatory);
  **`PostCompact` and `ConfigChange` → WIRE** (unique fields, and ConfigChange is decision-class);
  **`UserPromptExpansion` → DROP** (redundant with the already-wired `UserPromptSubmit`).
  Also recorded: `PermissionRequest`'s `tool_use_id` is always `""` (0 of 3,641 archived records), so
  `cc-permission-beacon.sh`'s grant-vs-deny attribution is **silently inert today** — a live defect,
  not a plan item. Refutation still missing for `permission` and `provider` only (§ 3d), not three
  groups as previously stated. Method lesson added to § 5: a zero-process snapshot is not death, and
  that error was made by this plan's author about the plan's own instrument.
- **2026-09-06** — **W1 + W2 DONE. The measurement is complete: 31/31 events on 220 and 27/27 on 114
  carry a verdict from a command that was run** (§ 3 table, § 3a commands). The two provisional
  non-verdict states are gone from this file entirely. Method: a 15-agent ultracode Workflow
  (static-read → probe → adversarial-refute, pipelined over 5 event groups) plus lead-run probes; the
  workflow died after 8 of 15 returns, so three groups lack an independent refutation (§ 3d) — their
  verdicts were read by the lead directly out of the raw payload logs, which outlived the agents.
  **Both HOLDs discharged** (§ 3c): `MessageDisplay` ≈1 fire per ~740 displayed chars in a TUI / 1 per
  message headless; `PostToolBatch` N:1 per batch. **Three of the four highest-value unknowns resolved**,
  including the one that gated the close-integrity idea — `prompt` hooks DO attach to `Stop` (proven by
  an 8-deep block loop), are refused on `SessionStart`, and the gate is `toolUseContext` at the call
  site rather than any event list. **Five dispositions changed** and are argued in § 3.
  **Surface bigger than the plan knew:** six handler types, including an `mcp_tool` type and a
  **`function`** type — the thing #91870 proposes — already shipping on 2.1.220.
  **Corrections to this plan's own § 1:** `claude doctor` prints no event list (the cited free
  instrument does not exist), the 27/31 census was circular and is now re-derived from each binary's
  enum literal, `--settings` MERGES rather than replaces, and an unknown event name is silently accepted.
  **Cost:** ~25 headless invocations; two triggers found that cost zero (`--init-only`, and an
  unauthenticated config dir for `StopFailure`).
  **Incident:** the `WorktreeRemove` probe left `core.bare=true` on the shared checkout — the
  `--settings` merge ran the live `WorktreeCreate` provider against the real repo despite a /tmp
  subject. Latent, not yet breaking; repair filed as backlog `d49917bc4e9e`. Lesson in § 5.
- **2026-09-05** — Plan created. Phase 1 at 7/15 events measured, 1 hostile, 12 owing work. Exit-code
  repair landed (`2d003a521`) after a first attempt (`a53632ae1`) was auto-reverted for breaking
  `bash-audit-attrib.bats`; the re-fix reads `.tool_response.exitCode` when present and derives from the
  event otherwise, so both contracts hold. 23/23 related suites green with a vacuity guard.
