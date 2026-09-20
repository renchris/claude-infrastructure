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
