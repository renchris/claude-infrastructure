# Slot: ledger. Why the LEFT close read ✅, and how the ledger's ✅ should relate to "Good to close: no"

Worktree `close-verdict-first` @ `ec25d5cb7`, 2026-10-10. Read-only on tracked files. Scratch files are in `/tmp/cvf-ledger/`.
Each number is labelled with how it was obtained.

## Answer first

**Recommendation: option (3), both.** Conviction **88%** overall. The parts:

1. **The verdict owns line 1. The ledger glyph becomes a clause.** Conviction 88%. This needs no D6 change, because D6 tests *containment* of `$RUNG` in line 1, so `❌ Not good to close — … · ledger ✅ clean & landed` passes as it stands. It does need **D3 taught polarity first**. A negative verdict on line 1 matches `CA_SETTLED` (it contains `good to close` and `✅`). It also usually matches `CA_RETRACT` (`remain`, `yours`, `pending`, `but`), so D3 would block an honest no.
2. **wrap-ledger's ✅ READOUT stops claiming task completion.** Conviction 92%. Replace `✅ Complete & live on trunk — nothing to do.` and the four `✅ Complete & landed — …` variants with git-only wording, e.g. `✅ Clean, landed & live — git only; whether the task is done is the verdict's call.` The machine field `RUNG=✅` is **unchanged**. No test pins the wording and no code parses it.
3. **(Ledger-side, new.) `SCOPE=met` must stop meaning "a DoD file exists".** Conviction 85%. This is the reason `operator-readout.sh` would have printed `✅ SAFE TO CLOSE` over the LEFT close's "no".

Why both: (2) alone leaves a green ✅ leading line 1 over a "no", and the glyph is what the eye reads. (1) alone keeps the model copying "nothing to do" verbatim (S1 and `/wrap` both say *verbatim*) into the same message as "Good to close: no". The ledger cannot know that the task is done, so it should not say so.

## 1. Why the LEFT close read ✅: signal by signal

The LEFT close is session `44091255-b12e-41c4-8aaa-0d4ddf21c6ec`, pane 16, cwd `/Users/chrisren/Development/claude-infrastructure`, close at **2026-10-10T16:15:41Z**. Its transcript is at `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/44091255-….jsonl`.

**Replay (measured).** I ran `wrap-ledger.sh --machine --session 44091255… ` in that cwd with `CC_PANE_ID=16`. Custody was stubbed to empty, because the only open custody row today (`fire-close-verdict-first`, 16:19:38Z) was opened *after* the close. I also set `WRAP_BACKLOG_TIMEOUT_S=40`. Result: `RUNG=✅ READOUT=✅ Complete & live on trunk — nothing to do. SCOPE=met REMAINDER=0 YOURS=0 FILED_MINE=0 CLOSED_MINE=2 BLOCKED=0 LIVE_SRC=ok LIVE_LAG=0`. Without the stub it reads 🔧 (custody 1, the fire of *this* session).

The ladder (`scripts/wrap-ledger.sh:2277-2445`) checks the following signals, in order:

| Signal (arm) | What it reads | LEFT close value | Could it see the open work? |
|---|---|---|---|
| ⛔ `count_blocking_decisions` | open class-C cc-decide packets filed by THIS sid | 0 | No. Nothing was a decision packet |
| 🔧 DIRTY | `git status` in cwd | 0 | No. The work was not in the tree |
| 🔧 REMAINDER | count of `- [ ]` lines in the lineage-filtered DoD file(s) | **0** | **No. See §2** |
| 📦 UNLANDED | `trunk..HEAD`, `git cherry` | 0 | No |
| 🔧 custody | `cc-custody list --open --cwd $PWD`, attributed by `originatorPane`/`notifyBack` == pane | 0 | **No.** Pane 182 (`fire-lr-stranded-husk`) was opened by **pane 180 in cwd `agent-context-sync`**, not by pane 16. "182 will mail this pane before it lands" is an *inbound* dependency, and no store records it |
| 🔧 resident members | team processes this lead started | 0 | No |
| 🔧 FILED_MINE | backlog rows `status=="open"` with `filedBy==sid`, `whyNotNow==""` and `condition==""` | 0 | **No.** The lead's own two open steps are rows `005dd549c80f` and `457c166ed9d6`. Both have `filedBy=44091255…` but `status=blocked` with `whyNotNow="not-yet-true: …"`, so the filter excludes them by design (they have a stated reason) |
| 🔧 UNCONVICTED | needs-human rows or packets with no conviction/receipt | 0 | No. The rows are `not-yet-true`, not `needs-human` |
| 🔧 close floor | backlog-shaped scope with CLOSED_MINE=0 | n-a | No |
| 🚀 live layer | live checkout lag and added files | ok, lag 0 | No |
| 👤 YOURS | `cc-backlog list --blocked` rows with **`.session == sid`** (or a fired peer's sid) | 0 | **No.** The two rows have `session: null` (cc-backlog stamped `filedBy` but not `session`). `be52a4c8a99f` (the zero-human marker) was filed by session `7b97011a…`. The "attended act canary" operator step is no row of this session's |
| ✅ default | everything above negative | **✅** | Wording: `Complete & live on trunk — nothing to do.` |

So the ledger was right about what it measures (git clean, landed and live, nothing dispatched by this pane outstanding). Its wording claims something it never measured: that the task has nothing left. The FLEET_V2 steps that remained were these:

- **Programme steps** (rule on 182's diff, first attended act canary, flip the zero-human marker, unblock two rows). These sit in rows with a `not-yet-true` reason, in rows filed by another session, and in free prose.
- **Inbound peer dependency** (182 will mail pane 16). This is in no store.
- **Operator step** (the attended canary). It is not filed as this session's row.

None of these has an arm.

**This is not a one-off (measured, Python transcript scan of the same session).** All 9 closes of session 44091255 on 2026-10-10 open with the identical line 1, `✅ Complete & live on trunk — nothing to do.`. **5 answer "Good to close: no"** (10:28, 11:12, 13:03 ×2, 16:15) and 4 answer yes. Line 1 carried **zero bits** about the verdict across the whole session. The 10:28 close even disclaims its own line 1 in parentheses: "That is the shared checkout's ledger; it can't see my hold commit, which is still landing from its own worktree".

**Fleet-wide (measured, `/tmp/cvf-ledger/scan2.py`).** Window: 14 days, the 5 transcript roots deduped by realpath, 1,959 files, close text deduplicated by its first 300 chars. **Of 483 closes whose line 1 starts with ✅ and that carry a `Good to close:` line, 207 answer no (42.9%).** In 190 of those 207 (91.8%), line 1 carries `complete`, `nothing to do` or `safe to close`. Caveat: a "close" here is the last assistant text before a user record, so hook-injected user records can split turns. Treat these as estimates of the class size, not exact counts. The earlier committed figure was **48 of 313 ✅ closes answer no** (`docs/research/close-shape-2026-08-23.md:113`, 15.3%, older window). The no-share has grown since D6 began forcing an explicit verdict.

## 2. The frozen-DoD REMAINDER: how it is computed and what it cannot see

`scripts/wrap-ledger.sh:666-704`:

- Sources: `dod_read_files "$PWD"` (repo-key store plus legacy file), filtered by `dod_filter_for` to this wave's lineage.
- `REMAINDER` = count of lines matching `^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]`. **That counts unchecked markdown checkboxes and nothing else.** `hooks/dod-persist.sh:106` states it: "wrap-ledger REMAINDER counts `- [ ]` boxes only".
- `SCOPE` = `unknown` if there is no DoD file, `open` if REMAINDER > 0, **otherwise `met`**.
- `DOD_SCOPE` (the newest `Scope (frozen):` line) is read, but only to test for `backlog|drain` (the close floor). Its content never feeds REMAINDER or SCOPE.

**A free-prose `remaining:` clause does not count.** The LEFT close's own current contract, in `~/.claude/autonomy/dod/repo-86523465733a9afe.md` at 2026-10-10T16:18:30Z, reads `Scope (frozen): FLEET_V2 origin lead — … cutover to recon/mode=act DONE 2026-10-10; remaining: rule on lr-stranded-husk-182's lr_recon diff, first attended act canary, then zero-human marker be52a4c8a99f and unblock 005dd549c80f/457c166ed9d6. …`. The ledger reads it as `REMAINDER=0 SCOPE=met` (measured in the replay above).

**The checkbox format is not what the producer writes (measured).** The rules tell sessions to freeze the DoD as *one line*, `Scope (frozen): …` (CLAUDE rule text: "restate the ask as one line"), and `dod-persist.sh set` writes exactly that. In `~/.claude/autonomy/dod/` (shell loop + grep):

- 77 DoD files, 76 with a `Scope (frozen):` line.
- **4 files with any checkbox at all.**
- **0 files with an unchecked `- [ ]` box.**
- 46 `Scope (frozen)` lines contain the word "remaining" (grep -c; some lines repeat across captures).

Across the 4 account transcript roots (23,696 `.jsonl` files, `rg -l`): **0 real `READOUT=🔧 Loose ends — N frozen-DoD item(s) remain`** and **0 real `REMAINDER=[1-9]`**. The single hit was a bats fixture quoted in a transcript.

**So the REMAINDER rung has never fired on a real session, and `SCOPE=met` reduces to "a DoD file exists".** The tests do not catch this. Every wrap-ledger and operator-readout fixture writes checkbox DoDs (`tests/wrap-ledger-research.bats:103-117`, `tests/wrap-ledger.bats:152,201,213,321,2449`), a shape production does not produce. This is the "fixture shape hides the bug" class in `.claude/rules/agent-operating-lessons-situational.md`.

## 3. Downstream: the certificate would have contradicted the close

`hooks/operator-readout.sh:1127-1141` (block state) and `:1861-1872` (standalone certificate) print **`✅ SAFE TO CLOSE — nothing of mine is open`** / **`✅ SAFE TO CLOSE — nothing is left on this side.`** under these conditions:

- `RUNG=✅`, and
- `scope_of` = `met`, and
- (for the block state) `CERT_WROTE=0` (a write turn).

The certificate is withheld only on `unknown` or `open`. At 16:15:41Z the inputs were RUNG ✅ and SCOPE met, so the certificate's conditions held, and it would have rendered beside a close that said "Good to close: no". I did not check whether it actually rendered: I did not read the operator-readout IDL for that turn. Rule text S2 already says "a rendered `✅ SAFE TO CLOSE` certificate does not replace [the verdict]". Even so, two green "safe" signals beside a "no" is the glance failure in its purest form.

## 4. Who consumes or pins the ✅ READOUT wording (`git grep`)

- **Producer:** `scripts/wrap-ledger.sh:2277` (default arm), plus `:2416` (`✅ Clean & landed — completeness UNKNOWN…`) and `:2432-2441` (four `✅ Complete & landed — live layer …` variants).
- **Tests pinning wording:**
  - `tests/wrap-ledger.bats:2455` checks only the prefix `^READOUT=✅`.
  - `tests/wrap-ledger-research.bats:97,100` pin the *absent-DoD* arm ("completeness UNKNOWN"), which can stay.
  - `tests/jev-evaluate.bats:619` and `tests/operator-readout-research.bats:227` grep "completeness UNKNOWN".
  - **No test pins `Complete & live on trunk — nothing to do` or `Complete & landed` as ledger output.**
- **The ~60 `tests/completion-assert.bats` hits** use `✅ Complete & live on trunk…` as *model-written close fixtures*. They pin hook behaviour on close text and are independent of what the ledger prints. They still pass unchanged, because the D6 check is glyph containment, not wording.
- **Other hits:**
  - `tests/install-core.bats:213` pins a *different* ledger (`$AC/bin/autonomy ledger`, `READOUT=✅ Complete — clean and pushed to origin/…`). It has the same conflation; flag it for parity, but it is out of scope here.
  - `scripts/drain-peer-findings.py:387` and `scripts/measure-harvest-latency.py:348` contain the string only as self-test inputs.
  - No code parses READOUT text: `hooks/completion-assert.sh` reads `RUNG`, and `scripts/handoff-fire.sh:6518` carries READOUT through verbatim.
- **Instruction text that teaches the conflation:**
  - `CLAUDE.global.md:704`, ladder row `✅ Live | genuinely complete AND on trunk | ✅ Complete & live on trunk — safe to close, nothing unsaved.` The rule text itself equates ✅ with "safe to close".
  - `hooks/lib/close-shape.sh:119` (S1 "READOUT's rung glyph and state clause verbatim").
  - `commands/wrap.md:174` ("Line 1 stays wrap-ledger's rung readout, verbatim").
  - `CLAUDE.rules.slim.10-session-close.md:22,148`.
- **Only `hooks/operator-readout.sh` (`scope_of`, :431-445) consumes the `SCOPE` field.** It accepts the closed vocabulary `met|open|unknown`. **Any other value falls through to the DOD/REMAINDER derivation, which yields `met`.** A new SCOPE value must therefore land in `scope_of` in the same commit as the producer, or the certificate gets *more* permissive (lesson "closed vocabulary swallows an unrecognized value").

## 5. The three options, judged against D6, D3 and the certificate

**(1) Verdict glyph wins line 1, ledger glyph demoted to a clause.**
- D6 (`completion-assert.sh:1262-1265`, `case "$ca_first" in *"$RUNG"*`) is containment, so a trailing `· ledger ✅ clean & landed` satisfies `line-1-rung` with **no code change**.
- **D3 is the blocker.** `CA_SETTLED='✅|safe to close|good to close|^…yes…|complete|…'` is polarity-blind. I tested four natural no-first lines against the live regexes:
  - **2 of 4 trip D3** (`… two FLEET_V2 steps remain (mine) … · ledger: ✅ …` and `✅ Clean & landed — … Good to close: no — two steps remain mine`).
  - The other 2 pass only because their wording avoided `remain`, `yours`, `pending` and `but`.
  - That is a false FAIL on an honest close, the worse error per the brief. D3 must treat `not good to close|good to close:? *no` as a *negative* settled verdict, which is consistent with withdrawal words. It should also drop `✅` from `CA_SETTLED` when the leading glyph is a verdict glyph and the ✅ sits in a `ledger …` clause.
- On its own, (1) leaves the model relaying "nothing to do" inside the ledger clause, because S1 and `/wrap` say verbatim.

**(2) Reword wrap-ledger's ✅ READOUT.**
- Zero test or parser blast radius (§4). Fixes the *words* in every consumer at once: the relay to line 1, `/wrap`, the self-close `why` in custody rows, and the operator-readout fallback.
- It does not fix the *glyph*. A green ✅ still leads line 1 under today's contract, and the eye reads that before the words.
- Changing the glyph itself (a new rung symbol) is rejected. `RUNG=✅` is keyed on by D6's gate (`RUNG ∈ {✅,👤}`), by the certificate, by `measure-selfclose-rung.py`, and by the ladder doc. The 2026-10-01 operator ruling also forbids a new glyph for scope.

**(3) Both, plus the SCOPE fix.** This is the recommendation.

## 6. Recommended change set (for the implementing session)

1. **wrap-ledger wording.** Conviction 92%. Edit lines 2277, 2432, 2434, 2439 and 2441 so that no ✅ arm says `Complete`, `nothing to do` or `safe to close`. Suggested: `✅ Clean, landed & live — git only; the verdict line says whether the task is done.` Converging variants: `✅ Clean & landed — live layer converging (…)`. Add a wrap-ledger test asserting that the default ✅ READOUT does **not** match `complete|nothing to do|safe to close` (case-insensitive), so the claim cannot drift back. Update `CLAUDE.global.md:704` (both the meaning column and the readout column), `close-shape.sh:119` and `commands/wrap.md:174` to call the ledger clause *evidence for* the verdict, not the verdict.
2. **SCOPE = met needs evidence.** Conviction 85%. In wrap-ledger, `SCOPE=met` only when the filtered DoD has ≥1 checked box and 0 unchecked. A prose-only scope (no boxes) gets a new value, `SCOPE=unchecked`, and operator-readout's `scope_of` accepts it **in the same commit**. It then withholds `SAFE TO CLOSE` (new abstain reason `cert-scope-unchecked`) and prints `✅ clean & landed — scope is prose, not machine-checkable`. RUNG is unchanged, so this cannot produce a false block. It only removes a false reassurance.
   - Optional, conviction 70%: if the newest `Scope (frozen|grown):` line has a `remaining:` clause, set `SCOPE=open` and `REMAINDER_PROSE=1`. Report it only, never as a rung. It is exact for the LEFT case, but it is a prose heuristic.
3. **Line 1 = verdict, ledger as a clause.** Conviction 88%; the shape itself is decided in the other slots. Gate the change to `line-1-rung` on D3 polarity landing first, with bats cases for the four lines in §5.
4. **Not recommended:** making the ledger try to see task scope (inbound peer mail, `not-yet-true` rows filed by the session, programme steps). Those are judgments, and a deterministic ledger that guesses them would manufacture 🔧s, which is the false-FAIL direction. The ledger's job is a **floor**: a non-✅ rung forbids "yes", and a ✅ rung *permits* yes and never *implies* it. S2 already says "The rung does not imply it". The wording must stop contradicting that.

## 7. Side findings

1. **Backlog sensors fail open on a cold cache (measured, `/usr/bin/time -p`).**
   - Timings: `cc-backlog list --all --json` 12.3 s and 12.7 s; `--blocked --json` 6.5 s and 6.2 s. `WRAP_BACKLOG_TIMEOUT_S` defaults to 5.
   - My first replay used a fresh TMPDIR (cold cache) and read `YOURS_SRC=error FILED_SRC=error`. That is YOURS=0 and FILED_MINE=0, so the 👤, filed-undriven, unconvicted and close-floor arms all fall through to ✅.
   - The cache (`_backlog_list`, :1004) is keyed on the backlog file's lstat, so every append makes it cold. How often a real Stop-hook close hits the cold path is **unmeasured**.
2. **YOURS keys on `.session`, but cc-backlog can write `session: null` with `filedBy=sid`.** Measured on `005dd549c80f` and `457c166ed9d6`. A blocked operator-step row filed that way would be invisible to 👤. These two rows are `not-yet-true` (not operator steps), so they are correctly not 👤 here. The key mismatch itself is worth a test.
3. **The ledger has no category for "my own step, deferred until something happens in the world"** (`not-yet-true` rows filed by the session). That is exactly the FLEET_V2 lead's open work. Surfacing it as a reported field (not a rung), e.g. `DEFERRED_MINE=N`, would give the model a fact to cite in "Good to close: no — …". Conviction 75%; not part of the recommendation above.
4. **The model's own judgment varied on the same dependency.** The 14:47 close said `Good to close: yes` while stating "Pane 182 … will mail me before landing"; the 16:15 close called the same dependency a no. That is outside this slot (verdict quality), and no deterministic hook should try to judge it.
