# W3i — an ingest that costs one round trip and fails closed

**The defect W3i removes, in one sentence:** `/limit-recover ingest` spends 6-9 model round trips,
6-8 tool calls and ~26.5 K **permanently resident** tokens per recovered session re-establishing a
precondition that is already written on disk — re-measured here over **all 24** of 2026-09-19's
recovery bundles rather than U12's sample of five, and `gaps_at_handoff == 0` in **24 of 24**.

Committed (not landed) on `lr100p/w3i`: `1fd0288af · 799f2d640 · bec58268d · c8eb42d2d` + this report.

---

## 1. What changed, by file:function

### `scripts/limit-recover/lr-ingest-verify.sh` (NEW, 312 lines) — the precondition as 13 predicates

U12 §6.1's clauses A-D, each printing its own value beside its verdict, receipt to
`$BUNDLE/INGEST-VERIFIED.txt`, rc 0 / 1. On rc 0 the receipt's **last line** is the one-line prompt
the launcher substitutes; on rc 1 no prompt line is emitted at all, so the launcher cannot `tail`
one off a refusal.

**Fail closed is the whole contract.** A clause that cannot be *evaluated* is a failure, never a
pass — a missing file, an absent field, an unparseable value, a `jq` that is not on PATH. rc 1 keeps
today's full ingest prompt with the failing clause named in it, so the degraded path is the one we
already ship: a false FAIL costs one expensive ingest, a false PASS costs the recovered session's
owed work. Every collection clause asserts its *container* first, because `null | length` is `0` in
jq and that zero would otherwise read as "nothing is owed" over a file whose field was renamed
(repo lesson `empty-vs-no-surface`).

**Three of U12's anchors were wrong against the bundles on disk.** Each is corrected with its own
case, and the brief's instruction to re-grep rather than trust a line number is what found them:

| U12 §6.1 says | on disk | consequence if shipped as written |
|---|---|---|
| `jq -e '.target_cfg == $t' locks/$SID.lock` | the lock's field is **`.to`** (`lr-transplant.sh:70-72`) | `null` ≠ target ⇒ **every** bundle fails C3 |
| `.teams[].members[]?` | `.teams` is an **OBJECT** keyed `led`/`other_team_dirs`/`wip_refs` | `jq` ERRORS (`Cannot index array with string "members"`) on every bundle |
| `[ "$CLAUDE_CONFIG_DIR" = "$(jq -r .target_cfg …)" ]` | the launcher sets that variable **from the same `$TCFG`** the manifest recorded | tautological read from the launcher — a clause cleared by construction |

C1 is therefore a **three-way** agreement: env, manifest, and the config dir re-derived from the
account NAME through the live `lib/account-map.generated.sh`. That third leg is the same live-layer
skew class the parser preflight exists for, caught before the pane instead of at it.

**A6 — `killed_inflight`, the clause W3 adds to U12's A.** Read from the run's own `events.jsonl`
(W2's `lr_state_append`), three states: a record with `killed_inflight > 0` ⇒ FAIL; the log present
and silent ⇒ PASS; the log **absent** ⇒ FAIL, because the precheck never ran and nothing here can
then say what the recycle interrupted. Post-W2 every admitted recovery writes at least
`lrh_state admitted gate` (`lr-handoff.sh:619`), so absence is a real signal rather than an
artefact — see §3 for what it costs on the historical bundles.

**`--no-clear` exists because clause D is a WRITE, and that was measured the hard way.** See §4.

### `scripts/limit-recover/lr-handoff.sh` — the prompt, and the bundle it points at

- **`:497` is now a placeholder.** The launcher heredoc composes `PROMPT` at **run time**, in the
  pane, seconds before the resume — so the decision rests on the state the session will actually
  wake into, not on the state at mint time (minutes older, and on the capacity-park path much
  older). `MANIFEST.ingest_prompt` now records the **fallback**, not a prediction.
  Fail closed three ways, each with a case: non-zero rc · a verifier **absent from the live layer**
  (the launcher names a durable `~/.claude` path, so a landed-but-not-deployed checker is simply not
  there) · a rc-0 receipt whose last line is empty or is itself a `FAIL`.
- **Ordering is load-bearing and is pinned.** The composition sits *after* the five `LR_*` exports,
  because `lr-ingest-verify` reads `LR_SUBMIT_TOKEN` from the environment and appends it to the
  fast-path line — that token is what makes SUBMITTED observable to W3's probe. The case fails if
  the stub reads `NO-TOKEN-IN-ENV`. `LRP_*` is the launcher's own namespace; nothing new is
  exported, so the closed list of five is unchanged (W2's case 20 still passes).
- **`HANDOFF-CONTEXT.md`: 87,858 B → 1,840 B.** On `09e64dcb/bundle-20260919T172203Z`, **86,888 B
  (98.6 %)** were 110 concatenated DoD captures from `dod_read_content`. The scope a successor must
  diff against is the LAST capture; the rest is history with a durable home. Now: the last capture
  (`awk` resets its buffer at each `^## ` heading, so a legacy store with no heading falls through
  as its whole content), capped 450, plus the store **directory** and the count — not the file list,
  which cost 200 B of a 2 KB budget for two absolute paths. The last assistant message is capped
  **500, not 2000**, with a pointer to the transcript. Re-measured end-to-end against the **real**
  DoD store (76 files, 89 lineage-matching captures) and the real 7.1 MB transcript: **1,840 B**.
- **`MANIFEST.json`: 4,379 B → 845 B.** `source_argv` was **3,477 B (79 %)** — the source process's
  full `ps -Eww` line, i.e. argv *plus its entire inherited environment* (`SSH_AUTH_SOCK`, the kitty
  listen socket, every PATH entry) copied into a file the recovered session reads. The three facts
  it was mined for are already their own fields: `runtime_model`, `runtime_effort` (parsed from the
  transcript's own tier, which beats argv when the session switched model mid-run) and
  `permission_mode`, all three asserted present by the acceptance case. A size fix and an exposure
  fix in one edit.
- **No backticks in either heredoc, and the file now says so in place.** Both the python block at
  `:433` and the launcher heredoc are heredocs **inside a command substitution**, and bash 3.2 — the
  `/bin/bash` this script declares, and the shell the launcher runs under — rescans that region and
  mis-parses a backtick there. One backtick in a comment produced
  `lr-handoff.sh: line 1114: unexpected EOF while looking for matching ``'` pointing **680 lines
  away** at a pre-existing comment, and `bash -n` under 5.3.15 reported the file clean. Repo lesson
  `the-deployment-interpreter-is-not-the-one-on-your-path`, live.

### `hooks/session-continue.sh` — `clear` refuses a sentinel another session armed

The sentinel is keyed on `(config-dir | cwd)` and **not** on the session, so any process running in
a directory clears whatever is armed there. Tolerable while `clear` was only ever typed by the
session that armed it; W3 makes a **recovery** run it. Two sessions sharing one checkout then give
the recovery a lever over a sibling's armed chain, and a cleared chain is **silent** — the sibling
simply stops being re-driven, with nothing anywhere saying why.

`set` already stamps the arming sid in `${f}.sid`; this is the reader. **Both** sids must be known,
so a bare shell `clear` (the documented operator park gesture, which carries no
`CLAUDE_CODE_SESSION_ID`) behaves exactly as before. rc stays 0 — a refusal is not an error, and a
non-zero would turn every caller without `|| true` into a failure. The mech budget is **not** spent
on a refusal.

### `scripts/limit-recover/lr-preseed-env.sh` — the two fullscreen gates

`fullscreenUpsellSeenCount` / `fullscreenDownsellSeenCount` added to `UPSELL_FLOOR`. The fullscreen
pair matters more than the six counters already there: a full-screen takeover at resume is not a
line of noise above the composer — it **owns the whole TUI**, so the typed prompt lands in nothing
and the recovery is a husk with a live process. Measured across all five config dirs:
`fullscreenUpsellSeenCount` is **3** in `.claude-next`, `.claude-secondary`, `.claude-tertiary`
(absent in the other two); `fullscreenDownsellSeenCount` is absent in all five.

---

## 2. RED before, GREEN after

Every case was run against the unmodified tree first. The red tails below are verbatim.

| # | case | arm | RED at base (verbatim tail) | GREEN |
|---|---|---|---|---|
| L1 | launcher: a PASSING verify replaces the ingest, carrying `run:` | source swapped to `HEAD:lr-handoff.sh` | `` `[[ "$output" == *"argc=7"* ]] …' failed`` → `argv[7]=</limit-recover ingest /var/…/bundle-20260920T001557Z>` | ✅ |
| L2 | launcher: a FAILING verify keeps the full ingest and NAMES the clause | same | same shape — `argv[7]=</limit-recover ingest …>`, no `lr-ingest-verify FAILED:` anywhere | ✅ |
| L3 | launcher: a verifier ABSENT from the live layer also fails closed | same | `` `[[ "$output" == *"argv[7]=</limit-recover ingest "* ]] …' failed`` (base emits it at `argv[7]` only because `--branch` is present; the *reason* line is absent) | ✅ |
| L4 | acceptance: `HANDOFF-CONTEXT.md` ≤ 2 KB, `MANIFEST.json` ≤ 1 KB | same | `` `! grep -q 'source_argv' "$B/MANIFEST.json" …' failed`` → `source_argv is still in the manifest` | ✅ |
| V1-V12, V14, V15 | the twelve clause cases + `--no-clear` + the checker's own preconditions | `lr-ingest-verify.sh` moved aside | `cp: …/scripts/limit-recover/lr-ingest-verify.sh: No such file or directory` — the subject did not exist | ✅ |
| **V13** | **D: a SIBLING session's armed sentinel is NOT cleared** | **`hooks/session-continue.sh` swapped to `HEAD`, verifier present** | `PASS D1 — auto-continue cleared: cleared → …/state/continue-36ff48305581890a` — the unmodified verb reported **success over another session's sentinel** | ✅ |

**Equivalence guard, labelled as such.** In L4 the **`HANDOFF-CONTEXT.md ≤ 2048`** assertion is
green in *both* arms (base produced 999 B) because the bats fixture's `$HOME` has an empty DoD
store — the fixture cannot reach the regime the bug lives in. Only the `MANIFEST` half of L4 is a
red-proof. The evidence for the HANDOFF-CONTEXT number is the **out-of-band measurement against the
real store**, run through the real `lr-handoff.sh` with `WRAP_DOD_DIR` pointed at
`~/.claude/autonomy/dod` and a real 7.1 MB transcript, everything else fixtured:
**87,858 B → 2,104 B → 1,840 B** (the middle figure is before the second tightening pass; the first
pass alone did not meet the 2 KB acceptance, which is why the caps are 450/500 and the pointer is a
directory).

**Not a test, but measured the same way — `lr-preseed-env.sh`.** Same fixture `.claude.json`
(`{up:3, down:2, ov:3}`), run through both versions: base → `{up:3, down:2, ov:99}`; W3 →
`{up:99, down:99, ov:99}`.

### Suites

| suite | Δ | result |
|---|---|---|
| `tests/lr-ingest-verify.bats` | **NEW** | **15/15** |
| `tests/lr-handoff-launcher-quoting.bats` | +4 cases, + both capacity gates pinned in `setup()` | **25/25** |
| `tests/session-continue.bats` | regression (the `clear` verb) | **37/37** — incl. cases 29-32, which are about this verb |
| `tests/session-continue-telemetry.bats` | regression | **12/12** |

`shellcheck -S warning -x` clean on all four `.sh` touched; `/bin/bash -n` (3.2) clean on all four.
Every bats file verified with `bats --count` before running.

---

## 3. Deviations from the spec, each with its reason

1. **"rc 0 on today's five bundles" is NOT met, and cannot be.** Run read-only over all 24 live
   bundles the script returns **rc 1 on 24/24**, and on **10 of 24 the only failing clause is A6** —
   those bundles predate W2's state log, so none carries `events.jsonl`. The rest additionally fail
   `B1` (the re-audit reads the target transcript **now**, and those sessions have been working for
   hours — an expected artefact of verifying old bundles late, not a defect) and `C2/C3/C4` where
   the session has since been transplanted again. Full per-bundle sweep:

   ```
   10  rc=1 fails=A6           6  rc=1 fails=A6,B1        2  rc=1 fails=A6,C3,C4
    2  rc=1 fails=A6,B1,C2,C3,C4   1  rc=1 fails=A6,C5    1  rc=1 fails=A6,B1,C5,D1
    1  rc=1 fails=A2,A6        1  rc=1 fails=A2,A6,B1
   ```

   The alternative — making an absent `events.jsonl` a PASS — is a fail-**open** on the one clause
   that exists to stop a fast path over killed work, so the acceptance number was the thing that
   gave. Fixtures of the verified bundle shape carry the green case instead, as the spec permits.
2. **`--no-clear` was added** (not in the spec). Clause D is a write; see §4. The prompt's own
   re-derive command now carries it.
3. **C1 is a three-way check**, not U12's two-way comparison, because the two-way form is
   tautological when read from the launcher (§1).
4. **The fail-closed prompt carries the run token too.** The spec's fail-closed text is
   `/limit-recover ingest $BUNDLE — lr-ingest-verify FAILED: <clause>`; both prompts now end with the
   run token, so W3's submitted-vs-armed discriminator still has something to look for on the
   degraded path. Without it the whole engagement oracle is blind whenever the fast path refuses.
5. **The last-assistant-message cap (2000 → 500) is outside the named anchors** (`:404-410`,
   `:443-444`). The ≤ 2 KB acceptance is unreachable without it: the DoD fix alone left 2,104 B.
6. **One commit covers both lr-handoff halves** rather than two. The brief scopes them as one
   bullet ("the launcher heredoc PROMPT composition **+** the DoD/argv trimming") and they share the
   file; splitting the hunks would have produced an intermediate state nothing verified.
7. **`tests/lr-handoff-launcher-quoting.bats` got +4, not +2.** The extra two are the
   absent-verifier fail-closed case and the acceptance measurement, which the spec asks to "measure
   and report" but names no home for.
8. **`lr-preseed-env.sh` keeps RAISE-ONLY semantics**, so the `fullscreenDownsellSeenCount` half is
   a **no-op on every config dir today** (the key is absent in all five). Writing a counter Claude
   Code has never written is a guess about a schema this script does not own, and a wrong guess is
   worse than the upsell. Seeding is a separate decision with its own evidence → §4.

---

## 4. Residuals handed to W5 / W7

1. 🚨 **A6 HAS NO WRITER, AND THAT IS THE ONE THING THAT KEEPS THE FAST PATH UNREACHABLE.** Nothing
   in the tree writes `killed_inflight` — `grep -rn killed_inflight scripts hooks bin tests` is
   empty apart from the reader I added. `handoff-fire.sh:7506` already **prints**
   `live_subagents: ${PRP_SA:-0}` from the read-only probe, and `lrh_precheck` already parses that
   probe's output for `verdict:`. The one-line fix is in `lrh_precheck` — **W2's function, which my
   brief forbids me to touch** — recording that count:
   `lrh_state admitted gate "token $LRH_ADMIT_TOKEN killed_inflight=$(…probe's live_subagents…)"`
   (the reader accepts both a top-level `.killed_inflight` and `killed_inflight=<n>` inside
   `.detail`). Until it lands, every real recovery fails A6 and takes the full ingest — correct, but
   it means **W3's measured saving does not materialise**. This is the highest-value single line
   left in the wave.
2. **Clause D is a write, and a verification run is indistinguishable from a relaunch.** Building
   this, a read-only sweep of the live bundles ran D 24 times and **disarmed two live sessions'
   continuation sentinels** — `28f07827`'s (wave-1 driver, armed 18:09Z) and `65186f1f`'s (armed
   **45 s earlier**, driving a wave). Both were restored byte-for-byte from
   `~/.claude/autonomy/idl.jsonl`, which records the step text and the arming sid on every `set`;
   the state dirs diff clean against the pre-sweep snapshot and `65186f1f` has since updated its own
   sentinel, so the restoration is confirmed live. `--no-clear` and the `session-continue` refusal
   both come from that incident. **The residual:** the IDL is the only reason this was recoverable,
   and nothing guarantees its retention window covers a future one. A `clear` that *archived* the
   sentinel it removes (one line, beside `${f}.mech`) would make the recovery local instead of
   forensic. Not taken here — it is `session-continue.sh` beyond the `clear`-verb scope I was given.
3. **`fullscreenDownsellSeenCount` seeding.** Raise-only leaves it absent on all five config dirs.
   Whether the recovery path should *create* startup counters is a product-schema judgement with a
   real downside; it wants one observation of the downsell actually rendering before anyone writes
   a key Claude Code has not.
4. **`B1` is time-sensitive by construction and nobody has bounded it.** The re-audit compares the
   target transcript **now** against the bundle's snapshot, so a recovery that sits parked on
   capacity long enough for a delegation to settle will fail B1 and take the ingest. That is the
   safe direction, but it means the fast path's hit rate is a function of park time and nothing
   measures it. `lr_state_current` already knows how long a run has been parked.
5. **`C2` counts transcript copies and refuses on >1**, which is correct, but a re-transplanted
   session (two of today's bundles) leaves the *old* bundle permanently unverifiable. A bundle that
   has been superseded should probably say so rather than fail three identity clauses — a `cc-lr
   status` (W5) concern, not the verifier's.
6. **`INGEST-VERIFIED.txt` is written by the launcher at relaunch, into the bundle.** W5's status
   renderer should read it: it is the only artefact that says *why* a given recovery took the
   expensive path, and its first `FAIL` line is the whole diagnosis.

---

## 5. One defect found outside my scope, named and left

`hooks/session-continue.sh`'s `clear` writes `${f}.mech` **unconditionally** — the comment at
`:170-171` argues it is "a property of THIS cwd, not of whether an agent-set sentinel happened to be
armed here". With the refusal added, a foreign-sid `clear` now returns before that write, which is
right. But the *non-refused* path still spends the mech budget on a cwd where nothing was armed,
which is how my first (pre-`--no-clear`) sweep left four stray `.mech` markers across two config
dirs. They were removed; the behaviour was not changed, because the argument for it is deliberate
and predates this wave.

---

## 6. W3i hardening pass (2026-09-20) — what the mutation pass found, and what is true now

An adversarial pass over `50b466066..7e899e090` returned **FAIL**: 7 defects and **11 of 37 mutants
surviving a fully green suite**. Every item below was reproduced by execution before it was touched,
and each fix carries a case that is RED on the unmodified tree. §§1-5 above are the record as the
first pass left it; this section states where it was wrong.

### 6.1 The seven defects

| id | the defect, in one sentence | RED on the unmodified tree (verbatim) | commit |
|---|---|---|---|
| **D1** | Clause D ran its clear under the **TARGET** config dir. The sentinel is keyed on (config-dir \| cwd) and the key the PRE-LIMIT arm used is the **SOURCE** account's, so D could never reach the sentinel it exists for — and the only sentinel at the target key belongs to whoever else works in that cwd on the target account. | with the pre-limit sentinel armed under the source dir: `PASS D1 — auto-continue cleared: nothing to clear — no sentinel was armed for this cwd: …/wt` | ``6ca8a06f7`` |
| **D2** | A6 returned `clause PASS A6` whenever `events.jsonl` existed and **no record carried the field** — and since nothing in the tree writes `killed_inflight`, that is the state of every post-W2 bundle. The suite's own CONTROL fixture was built to that shape, so it **pinned** the fail-open. | `PASS A6 — killed_inflight: no record in events.jsonl (state log ran; nothing reported a kill)` on the control fixture | ``9da1e2e10`` |
| **D3** | The fail-closed prompt carried no run token, contradicting §3 deviation 4. | `argv[7]=</limit-recover ingest … — lr-ingest-verify FAILED: FAIL C3 — lock /x/y.lock says to=…>` — no `run:` anywhere | ``d66bd6c7f`` |
| **D4** | `tests/session-continue.bats` was **36/37 in any ordinary session**, not 37/37: `sc()` handed the hook the RUNNING pane's `CLAUDE_CODE_SESSION_ID`, which the new foreign-sid refusal then correctly refused. Line 100's `grep -q "cleared"` had also gone decorative — the refusal text contains "nothing was **cleared**". | `not ok 1 base: set arms → status ARMED; clear disarms → status inactive` / `(in test file tests/session-continue.bats, line 101)` | ``bf2bc0428`` |
| **D5** | C5 passed whenever `git rev-parse --git-dir` failed — one rc for "genuinely not a repo" and for "git could not answer". | (case) `FAIL C5 — the manifest recorded branch feat/work but git cannot read …` was absent; the tree printed `PASS C5 — … is not a git repo` | ``933d9a910`` |
| **D6** | The sibling-sentinel refusal required BOTH sids to be known, and `set` writes `${f}.sid` only when the session HAS an id — so it was strongest over agent-armed chains and **inert over the operator's own** anonymous parks. | a sentinel armed with no sid was cleared by a foreign session | ``854454413`` |
| **D7** | The receipt printed `PASS D1 — auto-continue cleared: <value>` for every non-error outcome, and the composed prompt asserted "auto-continue cleared" unconditionally. | `the PROMPT claims a clear that did not happen: Resumed in place on next2 … (config dir, session id, transcript path, lock target, source tombstone, branch, auto-continue cleared) …` | ``6ca8a06f7`` |

**D1 and D7 are one hunk, and that is a deviation stated rather than hidden.** There is no version
of clause D that both addresses the right config dir and keeps a label naming one outcome for four:
the new clause reads its label off its value, and the prompt carries that value. Splitting them
would have produced an intermediate commit whose own tests asserted the false label — the shape
`stale-assertion-becomes-an-inverted-guard` warns about.

### 6.2 The two polarity decisions, with the argument each needs

The file's contract is *"a clause this script cannot EVALUATE is a FAILURE, never a pass"*, so a
deviation from it needs an argument and so does a change that makes the gate stricter.

**A6 (D2) — present-but-silent is UNEVALUABLE, not zero.** A log that never recorded the value does
not say the value was zero. `grep -rn killed_inflight scripts hooks bin` still finds only this
gate's reader, so "present and silent" is the shape of *every* bundle W2 writes, and the old arm
would have cleared all of them having measured nothing. Cost, named: until a writer lands (residual
1 — one line in `lrh_precheck`, W2's function) A6 refuses every real recovery and the fast path
stays unreachable. That is the same direction the absent-file arm already took.

**C5 (D5) — the manifest is the second source that makes a non-repo evaluable.** `rev-parse`'s rc
cannot separate "not a repo" from "git could not answer", so the rc alone can never earn a pass.
`lr-handoff` records `.branch` only when the cwd WAS a git checkout (it emits no `--branch` flag
otherwise — `tests/lr-handoff-launcher-quoting.bats` case 5), so an ABSENT branch field is the
bundle's own statement that this tree never was a repo. Two sources agreeing earns the pass; a
`command -v git` arm covers the third world. The CONTROL case pins the pass so the fix cannot
degrade into a blanket refusal.

### 6.3 Clause D is now two clauses

| | key it reads | what it may do |
|---|---|---|
| **D1** | `source_cfg \| worktree` — where the PRE-LIMIT continuation was armed | clears, as this session's own sid; ours to remove, which is why the ownership guard lets it through. An ABSENT `source_cfg` is a FAIL, never a "cleared" over a guessed directory |
| **D2** | `target_cfg \| worktree` — what the RECOVERED session's Stop hook will read | **never clears a stranger.** Nothing armed ⇒ PASS · armed by this sid ⇒ cleared (a second recovery back onto an account this session has run under) · armed by anyone else ⇒ **FAIL**: `hooks/session-continue.sh:1176` would clear-and-ignore it on the recovered session's own first Stop, silently disarming a live sibling in the cwd it is resuming into |

The verdict line's clause count is **counted**, not written down — the literal `13` would have
survived the 14th clause landing.

### 6.4 The eleven surviving mutants, and the case that now kills each

A clause with no case that dies on its mutation is decorative: it can be deleted, inverted or forced
true and every run still reads `ok`. Two of the eleven were not clause bugs but **fixture reach**
failures — the acceptance case for the ≤2 KB budget was an equivalence guard on the axis it claimed
to measure.

| mutant | the arm it survived in | the case that kills it |
|---|---|---|
| **M1** | B1's predicate forced true — B1 had **no failing arm at all** | `M1: B1 refuses a re-audit that finds an OPEN delegation` (an `Agent` tool_use with no tool_result) |
| **M2** | B1's unreadable-transcript arm | `M2: B1 fails CLOSED when the target transcript cannot be read` |
| **M3** | C2's count — 0 copies and 5 copies both passed | `M3: C2 refuses BOTH counts it is written for — zero copies and two` |
| **M4** | C5's detached-HEAD arm | `M4: C5 refuses a DETACHED HEAD` |
| **M5** | C1's unset-`CLAUDE_CONFIG_DIR` arm — unreachable because every case passes one **on purpose** (correct hermeticity, and it made the arm dead) | `M5: C1 refuses an UNSET CLAUDE_CONFIG_DIR` (`env -u`) |
| **M6** | A3's `spawned == settled` half — the existing case deletes only `.delegations.open` | `M6: A3 refuses spawned ≠ settled` (open=0, spawned=2, settled=1) |
| **M7** | D's non-executable-hook arm | `M7: D fails closed when session-continue.sh is not EXECUTABLE` (both D clauses assert) |
| **M8** | `clause()`'s `tr '\n\r\t' ' ' \| cut -c1-200` — the guard against a FAIL value injecting a newline into a prompt typed into a TUI composer | `M8: a clause VALUE carrying a newline is normalised to ONE line, and capped at 200` — the value is read out of the bundle's own JSON with `jq -r`, which emits a real newline for a `\n` |
| **M9** | the launcher's THIRD fail-closed arm: rc 0 whose receipt does not end in a prompt. The report claimed "FAIL CLOSED, THREE WAYS" and two were tested | `M9: … all three shapes` — the `case` enumerates a verdict line, an empty line and a FAIL line, and each is driven, because deleting ONE pattern leaves the other two green |
| **M10** | the 450-char DoD cap | `M10/M11: BOTH size caps are load-bearing` |
| **M11** | the 500-char last-assistant cap | same case, its own marker |

**Why M10/M11 survived, and what changed.** §2's equivalence-guard note said the `HANDOFF-CONTEXT.md
≤ 2048` assertion was green in both arms because the fixture `$HOME` has an empty DoD store — and
then left it there. An assertion green in both arms cannot pin a cap, so **both levers were
removable with the suite green** and the 1,840 B number rested entirely on an out-of-band
measurement no CI run repeats. The new case reaches the regime: a `WRAP_DOD_FILE` whose last capture
is ~2.6 KB and a transcript whose last assistant message is ~3 KB, each carrying its **own** marker
past its own cap (`DODTAILMARK` at +600 chars, `TAILMARK` at +495), so removing either cap is
attributable to that cap. Two control assertions come first — both fixture sources are asserted
oversized — so a green is a fact about the caps and not about an empty store.

### 6.5 Suites after the pass

| suite | before | after | note |
|---|---|---|---|
| `tests/lr-ingest-verify.bats` | 15 | **30** | +D1/D2 clause cases, +A6 silence, +C5 unevaluable + its control, +D7, +M1-M8 |
| `tests/lr-handoff-launcher-quoting.bats` | 25 | **27** | +M9 (three shapes), +M10/M11; three `A && B` assertions split (the liveness linter reported them DEAD — `and-absorbed`) |
| `tests/session-continue.bats` | 37 (36 in any ordinary session) | **41** | +foreign-sid discriminator, +D6 anonymous-owner case, +its control, +the `[ -f "$f" ]` equivalence guard |

`shellcheck -S warning -x` clean on all three `.sh`; `bats --count` run on every bats file before
running it; `python3 scripts/bats-assert-liveness.py` exit 0 on all three suites.

**One standing red that is NOT this diff's**: `scripts/pipefail-sigpipe-lint.sh` reports
`scripts/handoff-fire.sh 6 (was 4)`. That file is not in this diff (`git diff --stat HEAD --
scripts/handoff-fire.sh` is empty and its last commit predates `50b466066`), it is owned by the
sibling `lr100p/w3p` worktree, and the allowlist count is a pre-existing branch condition. Named
here so the next reader does not attribute it.

### 6.6 Residuals — what §4 said, and what is true now

1. **A6 still has no writer, and D2 made that MORE binding, not less.** §4.1 was right: nothing
   writes `killed_inflight`, and the one-line fix lives in `lrh_precheck` (W2's function, outside
   this brief). Until it lands, A6 refuses every real recovery — which is now also true of the
   present-but-silent state, i.e. of every post-W2 bundle. **This is the single highest-value line
   left in the wave**, and W3i's own change is what makes it the only thing standing between the
   gate and its measured saving.
2. **D2 can refuse over a live sibling, and that is deliberate.** If any session on the TARGET
   account has a continuation armed in the recovered session's worktree, the fast path refuses and
   the recovery takes the full ingest. Safe direction, and rare — but it is a new refusal class the
   status renderer (W5) should be able to name from `INGEST-VERIFIED.txt`.
3. **The CLI `clear` is now stricter than the ACTUATOR, on purpose and asymmetrically.** Actuation
   (`:1176`) clears-and-ignores a foreign sentinel; the CLI verb refuses one. The asymmetry is
   right — the actuator IS the session whose Stop is being decided, while a CLI `clear` may be a
   recovery, an operator, or a sibling — but it means a post-recycle successor in the same cwd can
   no longer clear its predecessor's sentinel by hand. Its own first Stop still does.
4. **§4.2's archive-on-clear is still not built.** The IDL remains the only reason the 2026-09-19
   incident was recoverable, and nothing guarantees its retention window covers the next one.
5. **B1 is still time-sensitive and still unbounded** (§4.4), and M1 now pins the direction it fails
   in rather than the bound it lacks.

### 6.7 How each kill was proved

Every row below was produced by the harness at `/tmp/w3i-mutants.sh`: apply ONE exact-string mutation
(the patcher exits 3 rather than silently no-op on an anchor miss), run the ONE case named for it,
record the rc, restore the subject and verify its sha256 at the end. A row that comes back rc 0 means
the case is decorative — the same verdict the adversarial pass returned, re-derived here.

| mutant | the mutation applied | verdict |
|---|---|---|
| `M1` | `if [ "$_o" = 0 ] && … ; then` → `if true; then` (B1 always passes) | **KILLED** |
| `M2` | B1's unreadable-transcript arm FAIL → PASS | **KILLED** |
| `M3` | `if [ "$_hits" = 1 ]; then` → `if true; then` | **KILLED** |
| `M4` | C5's detached-HEAD arm FAIL → PASS | **KILLED** |
| `M5` | C1's unset-`CLAUDE_CONFIG_DIR` arm FAIL → PASS | **KILLED** |
| `M6` | A3 drops the `[ "$_sp" = "$_se" ]` conjunct | **KILLED** |
| `M7` | `if [ ! -x "$SC" ]; then` → `if false; then` | **KILLED** |
| `M8` | the `tr … \| cut -c1-200` normaliser removed | **KILLED** |
| `D2A6` | A6's `-1` arm restored to PASS (the pre-fix fail-open) | **KILLED** |
| `D5C5` | C5's unevaluable-git arm restored to PASS (the pre-fix pass) | **KILLED** |
| `D1CFG` | `sc_run "$SRC_CFG"` → `sc_run "$TCFG_M"` (the pre-fix config dir) | **KILLED** |
| `M9` | the launcher's `''\|FAIL*\|verdict:*)` → `'')` | **KILLED** |
| `M10` | the 450-char DoD cap removed | **KILLED** |
| `M11` | the last-assistant cap 500 → 2000 (the pre-W3 value) | **KILLED** |
| `D6OWN` | the clear guard restored to "both sids must be known" | **KILLED** |
| `D6BUD` | the `[ -f "$f" ]` conjunct removed from the clear guard | **KILLED** |

Three of the rows are the fixes' own RED proofs rather than mutants of new guards: `D1CFG` restores
the target-dir clear, `D2A6` restores the `-1 ⇒ PASS` arm, `D5C5` restores the unevaluable-git pass,
and `D6OWN` restores the both-sids-required guard. `D6BUD` is what makes the `[ -f "$f" ]`
equivalence guard a guard: it is green in both arms of the D6 change and dies on the mutation that
removes the conjunct, which is the only evidence that assertion has power.

## 7. W3i round 4 (2026-09-20) — B3's verdict, and the flag that failed open on the other side

Round 3 died mid-run on an `ENOTFOUND` after three commits. This section (a) re-verifies those three
by execution rather than inheriting their claims, (b) answers B3 — the question §6 left open —, and
(c) records the one defect that survived both hardening passes.

### 7.1 The three blockers, each re-measured on this tree

| | claim | how it was re-checked | result |
|---|---|---|---|
| **B1** | an unchanged trunk suite is red from this branch's hook change | `bats -f "double-block" tests/completion-assert.bats`, run **with** an ambient `CLAUDE_CODE_SESSION_ID` (the condition that made it red) | **5/5 ok**, including `double-block CONTROL: the marker is per-STOP — a later silent Stop convicts again`. The control was not loosened: `clear`'s guard became opt-in, so the operator's bare verb — which that case drives — is trunk's verb again |
| **B2** | pipefail | `bash scripts/pipefail-sigpipe-lint.sh` after `git rebase origin/main` | **rc 0**, `clean (allowlist honoured)`, 1395 verdicts carried / 39 proven fresh. The sibling's two `handoff-fire.sh` drains are on trunk and came in with the rebase |
| **B3** | the gate admits nothing | full 69-bundle sweep re-run, plus a corrected counterfactual | §7.2, §7.3 |

The twelve mutants §6.7 records were also re-run against this tree rather than quoted:
**12/12 KILLED, survivors none**, subject sha256-verified restored after every row.

### 7.2 B3 — the rc distribution per clause, over all 69 bundles, before and after

Protocol both arms: `--no-clear`, `CLAUDE_CONFIG_DIR` taken from **each MANIFEST's own** `target_cfg`,
every bundle under `~/.reso/limit-recover`. BEFORE = tree at ``a14f2edbd`` (round 3's starting point);
AFTER = ``199261ca6`` rebased onto today's `origin/main`, re-run afterwards on ``a4bec3973`` and
**bit-identical** — §7.6's fix cannot reach a `--no-clear` sweep, where clause D asks `status`.

| clause | FAIL before | FAIL after | Δ |
|---|---|---|---|
| A0 | 1 | 1 | |
| A1 | 17 | 17 | |
| A2 | 42 | 42 | |
| A3 | 35 | 35 | |
| A4 | 35 | 35 | |
| A5 | 6 | 6 | |
| A6 | 68 | 68 | |
| B1 | **50** | **46** | **−4** |
| C1 | 0 | 0 | |
| C2 | 25 | 25 | |
| C3 | 67 | 67 | |
| C4 | 7 | 7 | |
| C5 | 24 | **25** | +1 |
| D1 | 10 | **11** | +1 |
| D2 | 10 | **11** | +1 |
| **rc=1** | **69 / 69** | **69 / 69** | |

**The three `+1`s are one bundle and they are the world moving, not the gate.** A per-bundle join of
the two arms shows exactly five rows differing: the four B1 flips, and
`7f533f05…_bundle-20260919T223034Z` going `A2,A6,C3` → `A2,A6,C3,C5,D1,D2` — its worktree was reaped
between 11:57 and 16:05. That is C7's arms firing correctly on a live reap, and it is also why the
figure is quoted with its timestamp: **a sweep of this store is a sample, not a constant.**

**The four B1 flips are the fix.** `28f07827…174936Z`, `4101dbdf…153655Z`, `a99681dc…153937Z`,
`c0f857b6…222337Z` — each a bundle whose nonsuccess notifications were already recorded in its own
audit, i.e. the clause refusing a state it was cut from.

**rc is 69/69 in both arms, and that is the honest headline.** Nothing in this wave made a single
bundle on disk admit.

### 7.3 Why 0/69 is not a verdict about the gate — and what the number actually is

Two clauses account for the floor: **A6 fails 68 of 68 reached, C3 fails 67 of 69.** Both are gated
on an artifact whose **writer is younger than the bundles**:

* `killed_inflight` — the writer landed in this wave (``a44c45e0a``). `grep -rn killed_inflight
  scripts hooks bin` found one reader and no writer before it.
* the split-brain lock — `~/.reso/limit-recover/locks/` holds **one** lock, dated 2026-09-20 05:01,
  against the **65 of 69** bundles that carry a `transplant.json`.

For C3 that raises the question A6 already answered badly once: *is the clause passable at all, or is
the lock removed on success?* Measured, not assumed — `grep -rn 'rm .*\.lock' scripts/limit-recover/`
returns **nothing**, and `lrt_already_done` (`lr-transplant.sh:57-62`) reads the lock as a durable
idempotency receipt. The lock persists; C3 is passable, and the single live lock is simply the only
transplant performed since that writer landed.

**The counterfactual.** For each of the 33 current-schema bundles, supply *only* those two artifacts
and read everything else — transcripts, tombstones, worktrees, sentinels, the account map — live.
Nothing under `~/.reso/limit-recover` is written; each bundle is copied first.

| | over 33 current-schema bundles |
|---|---|
| **rc=0 (ADMITTED)** | **11** |
| rc=1 | 22 |
| A3 · A4 · A5 · A6 · C1 · C3 | **0 each** |
| B1 | 15 |
| A2 | 7 |
| C4 · C5 | 5 each |
| C2 | 3 |
| A1 · D1 · D2 | 2 each |

**So the fast path is not a feature that does not exist: it admits about a third of modern-schema
recoveries.** A6 and C3 — **135 of the 396** clause failures the live sweep records — go to **zero**
the moment their writers have run.

⚠️ **That 33% is a PROJECTION, not a measurement, and must be quoted as one.** No bundle on disk was
cut by today's writers, so no run of this gate has ever admitted anything. The falsifier is cheap and
dated: **the first bundle cut after this wave.** If A6 or C3 fails on it, the writer is not reaching
production and this whole paragraph is wrong.

**A harness defect found on the way, worth recording because it inverted a number.** Round 3's
counterfactual wrote the lock pointer with `jq '.lock=$l' "$work/transplant.json"` behind an
`[ -f ... ]` guard. **Five of the 33 bundles carry a present-but-EMPTY `transplant.json`** (the
second and later bundles of a repeatedly-bundled sid), and `jq` on empty input emits nothing, so the
pointer went into a void, `mv` installed an empty file, and the gate fell back to the derived path —
which the harness had not created. Those five were then charged a **C3 failure the gate never made**.
Testing parseability instead of existence takes cf's C3 residual from 5 to **0**. The gate itself is
unaffected: its three readers of that file (`.target_transcript`, `.lock`, `.tombstone`) each fall
back to the canonical path, so an empty receipt changes no verdict — only the harness measuring it.

### 7.4 Every residual refusal is a TRUE statement about its bundle

Judged clause by clause over the 22 that still refuse under the counterfactual:

| clause | n | the refusal, and why it is true |
|---|---|---|
| **B1** | 15 | 12 are `NEW-nonsuccess≥1`: a delegation genuinely failed **after** the bundle was cut. Spot-verified on `12e163a9…221703Z` — the one id B1 calls NEW is absent from that bundle's own `audit.json .delegations.notifications` (which recorded 2 others). Every failing bundle HAS a baseline, so none is the no-baseline arm. The other 3 are "no readable target transcript under `target_cfg`" — and C2 fails on the same 3 |
| **A2** | 7 | real in-flight work: `counts.gaps` 17 and 7 on two bundles, `counts.waiting` 2-14 on five |
| **C4** | 5 | two sids (`07e30aeb`, `4bc1159f`) with neither lock nor tombstone — transplants that never completed |
| **C5** | 5 | 2 reaped worktrees, 2 `pool/slot-*` fleet branches, 1 manifest recording neither worktree nor cwd |
| **D1/D2** | 2 | the same 2 reaped worktrees, now named as such rather than as `exited 97` |
| **A1 · C2** | 2 · 3 | gaps at handoff; the 3 missing transcripts above |

**Nothing here is the gate being wrong about the world.** There is no refusal left to loosen.

### 7.5 What the gate should do instead

1. **Loosen nothing.** Each of the 22 is a true statement, and 135 of the 396 live failures are
   writer-age, not design. The work is landed; what remains is for the writers to run.
2. **Quote the saving against 33%, never against 100%.** A token-saving claim computed over all
   recoveries is the defect this project keeps finding — the fast path is a third of them, projected.
3. **B1 at 15/33 is the binding constraint, and it is a freshness clause doing its job.** Its failure
   rate is a function of how long a bundle sits before ingest, not of the gate. If the admit rate
   matters, cut the latency; do not weaken the clause that catches a delegation dying under us.
4. **Date the falsifier.** The first bundle cut after this wave settles A6 and C3 in one run. Until
   it does, `0 of 69` is what this gate has actually achieved and the close should say so.

### 7.6 The defect this round found: `--if-mine` failed open on an absent CALLER identity

§6.1 D6 removed a refusal keyed on evidence **the arm** need not have written. The same shape
survived on the other side of the call. The guard read

```sh
if [ "$_sc_ifmine" = 1 ] && [ -f "$f" ] && [ -n "$_sc_cur" ] && [ "$_sc_owner" != "$_sc_cur" ]; then
```

so a caller that **passed `--if-mine`** and carried no session id skipped the guard entirely.
RED, reproduced by hand before anything was touched — a sentinel armed as `sidA`, then:

```
armed:  ARMED (0 continuations, sid=sidA): the owner's step
rc=0  out=cleared → …/state/continue-57abbbbe85769147
after:  inactive
```

`--if-mine` asks exactly one question — *did I arm this?* — and a caller with no identity has already
answered it. The test is now positive proof of ownership rather than absence of a mismatch: proceed
only when the caller names itself **and** that name is the one recorded at arm time. The bare verb is
untouched — `_sc_ifmine` is 0 without the flag, so the operator's park gesture never reaches this
test, and `clear CONTROL: the operator's OWN bare-shell clear still disarms an anonymous sentinel`
holds.

A second arm was needed for a second world: with the arm anonymous **and** the caller anonymous, both
sides are `""`, `"" != ""` is false, and a bare inequality would clear on a **coincidence of
absence**. Two unknowns are not a proof of identity.

Suite 44 → 46. Both new cases were RED on the unmodified tree, verbatim:

```
not ok 1 clear --if-mine: a caller that recorded NO sid is refused — it cannot be the armer
#   `[[ "$output" == refused\ * ]] || { … }' failed
# an anonymous CALLER cleared sidA's chain: cleared → …/cfg/state/continue-2576ad07f60071fb
not ok 2 clear --if-mine: neither side identified is still a refusal, not a match on two empty strings
# two empty sids compared EQUAL and cleared: cleared → …/cfg/state/continue-c16b3a8d3002dd5e
```

This is latent rather than live for the shipped caller: `lr-ingest-verify` resolves
`SID="$(mval '.sid // "ABSENT"')"`, which is never empty, so clause D always names itself. It is the
contract of the flag that was wrong, and the next caller is the one that would have paid.

### 7.7 Mutation score of this round's own additions

Four mutants, each run against the ONE case named for it, subject restored and sha256-verified after
every row (`scratchpad/w3i/mutants4.py`):

| mutant | the arm it deletes | verdict |
|---|---|---|
| `CALLERID` | the widened test restored to `[ -n "$_sc_cur" ] && …` (the pre-fix guard) | **KILLED** |
| `EMPTYMATCH` | the widened test reduced to the bare `[ "$_sc_owner" != "$_sc_cur" ]` | **KILLED** |
| `CURLABEL` | the `a caller that recorded no sid` fallback label | **KILLED** |
| `BLANKET` | the `[ "$_sc_ifmine" = 1 ]` conjunct — the control that the guard did not become unconditional | **KILLED** (3/19 red) |

**SURVIVORS: none.** `EMPTYMATCH` is what makes the second case non-redundant: it leaves case 1 green
(owner `sidA` ≠ caller `""` still refuses) and dies only on the anonymous/anonymous pair.

### 7.8 Residuals

* **A6 and C3 are unfalsified in production.** Both are now writer-backed and both read 0 under the
  counterfactual, but neither has been observed passing on a real bundle. First bundle cut after this
  wave settles it.
* **The 33% admit rate is projected.** It rests on a counterfactual whose two synthesised artifacts
  are named above; everything else in it is live.
* **`transplant.json` is written empty on repeat bundles of one sid** (5 of 33). No gate verdict
  depends on it — all three readers fall back — but the writer is in `lr-transplant.sh`, outside this
  wave's file set, and nothing currently notices a truncated receipt.
* **The `--if-mine` residual §6 stated is unchanged**: a third party that does not pass the flag can
  still clear a sibling's chain. This wave closed the recovery path, not the general shape.
