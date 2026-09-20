# W3p — the submission probe and an engagement oracle that a notification cannot satisfy

**Branch** `lr100p/w3p`, four commits on `50b466066`:
`453d416e2 · 259b09667 · 21d4132f9 · d43f694a9`.
W3's other half (`lr-ingest-verify.sh`, `lr-handoff.sh`, `lr-preseed-env.sh`,
`hooks/session-continue.sh`) belongs to a sibling writer and is untouched here.

**The defect W3p removes, in one sentence:** a detached `verdict=RECOVERED` certified that *some*
assistant turn happened after a wall-clock instant, which a background-task notification, a drained
peer message or a Stop-hook continuation all satisfy — so a pane whose ingest prompt was still
sitting unsubmitted in the composer was reported as a working continuation.

**The cure, in one sentence:** the per-run token lr-handoff already mints is now read back out of
the TARGET transcript, so "submitted" is a RECORD rather than a screen phrase, and engagement is
measured from that record rather than from the clock.

---

## 1. What changed, by file, with the measurement that motivated it

### `scripts/limit-recover/lr-submit-probe.sh` — NEW, 109 lines

`<cfg> <sid> <t0> <token>` ⇒ one line: `submitted <ts>` (a `type:"user"` record newer than `t0`
whose content carries the token) · `queued <ts>` (a `queue-operation`/`enqueue` record carrying it)
· `none`.

- **Three verdicts, because there are three remedies.** `submitted` starts the engagement clock;
  `queued` means a turn is running and a keystroke would enqueue a SECOND copy of the prompt;
  `none` means act. Collapsing them is what made the old verifier send five blind CRs.
- **A refusal is not `none`.** An unreadable transcript exits **3 with EMPTY stdout** and a cause
  line on stderr; missing args exit 2; no `/usr/bin/python3` exits 4. `none` is the answer that
  LICENSES A KEYSTROKE into a live pane, so a refusal that printed it would type into a session
  whose state was never read (memory `predicate-refusal-is-not-a-negative`; the last time this was
  conflated, 20 of 20 rows lied).
- **Tail-bounded, and that is correctness rather than speed.** The question is only ever about
  records newer than `t0` — captured immediately before the relaunch spawns — and a transplanted
  transcript is tens of MB that predate it. Measured on this box: **60–70 ms wall over 3 runs on a
  17 MB transcript** (`~/.claude/projects/-Users-chrisren-Development-lakehouse-lecture/a15b23d2….jsonl`),
  of which the 400 KB scan is the spec's ~19 ms and the rest is python startup. Cheap enough for the
  1 s poll it exists for. A `tail -c` starts mid-record, so the first line routinely fails to parse
  and is skipped — the same rule `lr_last_api_error` already runs on.
- **Two records cannot forge a submission:** a SIDECHAIN user record (a subagent's thread) and an
  assistant record echoing the token are both excluded.
- Read-only and re-runnable: a test hashes the transcript before and after two runs.

### `scripts/limit-recover/lr-fire-resume.sh` — the expect program

Three coupled changes, all of one shape: **stop asking the SCREEN for a PHRASE.**

1. **`LR_RE_READY` loses its third alternative**, the mode-cycling hint — 0 hits across CC 2.1.260's
   rendered status line, so it could only widen the pattern against a string the binary no longer
   paints. (Its literal spelling is deliberately absent from the file: the acceptance grep is a
   file-wide count, so a comment quoting it would defeat the check.)

2. **`timeout {}` becomes an 8 s QUIET ARM, and the main loop now runs on that budget instead of
   300 s.** At 300 s the arm was unreachable in practice — lr-handoff awaits the whole recycle
   inside 900 s and the watcher calls it dead at 180 s — so a READY phrase the binary had stopped
   painting meant the prompt was simply never typed and *nothing anywhere said so*. Quiet is the
   positive fact a booting TUI cannot fake: it paints continuously, so silence means the frame
   settled. The arm then reads the pane out of band (`it2 session read`) and types **only** on an
   affirmatively EMPTY composer.

   🚨 **Never a blind CR into a quiet pty.** A parked menu is quiet too, and Enter on the resume menu
   takes *"resume from summary"* — spends usage, loses the goal. `MENU`, `DRAFT` and `UNKNOWN` all
   park, print `✗ READY NEVER SEEN — prompt NOT typed: …` and record `READY-NOT-SEEN`.

   The screen verdict finds the composer by its **border runs** (a repeat of U+2500), never a
   literal phrase, and identifies a selector line as `❯` followed by an **ordinal** — because the
   composer box draws `❯` too, so "contains ❯" would call every healthy screen a menu. That parse is
   `composer_content()` from `handoff-fire.sh`, reproduced rather than shared because expect cannot
   call a bash function.

3. **The post-inject verifier becomes a poll of the probe.** 1 s ticks, ≤30 s; a `queued` extends the
   deadline to `RCY_ENGAGE_TIMEOUT`; a `none` at the bound buys **exactly one** more Enter, and only
   after the screen shows OUR OWN prompt still in the composer (`DRAFT-MINE`) — the 2026-07-11
   stranded-ingest case, a leading-`/` prompt whose first CR the slash-command autocomplete swallowed
   as a menu-select. Terminal state: `submitted` | `queued` | `FAILED:submit` | `INDETERMINATE:submit`.

   🚨 **Nothing in that block may `exit`** — expect exiting closes the master pty and kills the
   resumed session, which is the husk this project exists to prevent. Every path, failures included,
   falls through to `interact`; a test enforces the count at 0.

**The three questions the program asks the world** are exported as WHOLE shell programs
(`LR_SCREEN_SH`, `LR_NOTE_SH`) plus one resolved path (`LR_PROBE`), so Tcl hands each to `bash -c`
as ONE argv element and cannot mangle it — the same discipline the `LR_RE_*` patterns already use.
**Note for anyone editing this program:** its entire body is a single-quoted bash string, so an
apostrophe anywhere inside it terminates that string. Two of my own comments did exactly that and
were reworded; `shellcheck` caught it, `bash -n` on the file would have too, but a reviewer reading
the Tcl would not.

**Inject sleeps 2/1/1 → 0.3/0.2/0.2.** They are settling delays that keep the `^U`, the text and the
CR from coalescing into one paste, not waits for a remote event. 4 s of the old budget was pure
latency on every recovery, and the poll now MEASURES the outcome instead of guessing at it.

### `scripts/handoff-fire.sh` — `resume_engaged` gains `$4`, and the watcher gains `$16`

- **`resume_engaged <cfg> <sid> <t0> [<token>]`.** With a token the baseline stops being a CLOCK and
  becomes a RECORD: the newest user record carrying the token — the moment OUR prompt was accepted —
  and the qualifying assistant turn must be newer than THAT. A notification turn that arrived first
  is behind the baseline by construction.
- **No token record ⇒ rc 1, deliberately.** The prompt is not in the transcript, so there is nothing
  for a turn to be an answer TO. Falling back to the weaker clock test there would re-open the hole
  *silently*, on exactly the runs where it matters.
- **The token scan is its own heredoc, NOT an edit of the `PY` core.** `tests/lr-lib.bats` pins that
  core byte-identical against `lr-lib.sh:lr_engaged_after`; re-verified green here.
- **Watcher:** `$16` carries the token, the probe runs FIRST each tick, and a `submitted` emits its
  own `recycle-submitted` ledger row and run-state line. *Armed* and *engaged* have different
  remedies — a prompt that never left the composer is re-typed, one that landed and is waiting is
  left alone — and a single engaged/dead verdict cannot express either. The dead arm now names WHICH
  failure it is: *"submitted at T and never answered"* vs *"never reached the transcript at all"*.
- **`RCY_ENGAGE_INTERVAL` 5 → 1.** The poll is two cheap local file scans now, not an it2 round
  trip, so the old spacing bought nothing and cost up to 5 s per recovery plus a 5 s-quantised
  `within ${rcy_t}s` figure in the ledger row.

🚨 **The precondition that makes this half safe to land FIRST.** The token only reaches the
transcript if it is in the PROMPT, and that is the sibling writer's `lr-handoff.sh` change. So the
arming side **counts the token's occurrences in the launcher**: the export alone is 1, the export
plus the prompt is 2, and below 2 the token is **not passed** and the run falls back to the
wall-clock oracle *with a line saying so* (`claimed-outcome-vs-checked-outcome`: a degraded verdict
that does not announce itself is worse than the strong one it replaced). Without that count, landing
this half first would convict **every healthy recycle**. It self-arms the moment the lr-handoff half
lands, with no further edit here.

---

## 2. RED before, GREEN after

Both arms measured on this branch; the RED arm was produced by removing the new file
(`lr-submit-probe.sh`) and by restoring `git show HEAD:scripts/handoff-fire.sh`, then re-running.

| # | case | verbatim RED tail on the unmodified tree |
|---|---|---|
| 3 | probe: a `<task-notification>` user record WITHOUT the token → `none` | `/opt/homebrew/…/test_functions.bash: line 158: …/lr-submit-probe.sh: No such file or directory` · `[ "$output" = "none" ] \|\| { echo "$output"; false; }' failed` |
| 8 | probe: UNREADABLE is rc 3 with empty stdout, never `none` | `` `[ "$status" -eq 3 ]' failed `` |
| 12 | ACCEPTANCE: the running-turn chrome phrase is gone | `` `[ "$output" = 0 ] …' failed `` · `still present: 2` |
| 13 | ACCEPTANCE: the mode-cycling hint is gone from `LR_RE_READY` | `still present: 1` |
| 14 | the post-inject block contains ZERO `exit` statements | `post-inject exits: 1` |
| 15 | the expect program polls the probe | `the probe is not wired into lr-fire-resume: 0` |
| 16 | `resume_engaged` takes a token; the watcher is handed one | `resume_engaged signature: 0` |
| 17 | quiet arm: READY never matched, composer EMPTY → the prompt IS typed | no quiet arm exists; `grep -qF "GOT:[…]"` on an empty keylog |
| 18 | quiet arm: a PARKED MENU → NOTHING is sent, and it says so | idem — the pre-change `timeout {}` is silent and types nothing *and says nothing* |
| 19 | submit poll: a user record with the token → state `submitted` | idem — no state is ever written |
| 20 | submit poll: nothing in the transcript → ONE re-Enter, then `FAILED:submit` | idem — the pre-change loop sends up to FIVE CRs and writes no state |
| 21 | a token that never reached the transcript is NOT engagement | the pre-change oracle ignores `$4` and returns 0 |
| 36 | **notification turn BEFORE the submitted prompt is NOT engagement** | `` `[ "$status" -eq 1 ] \|\| { echo "a stale notification turn still satisfies the oracle"; false; }' failed `` · `a stale notification turn still satisfies the oracle` |
| — | `lr-resume-answer-width.bats` 6–11 (the LR_RUN fix) | `width 8: selector never moved off option 1 — keylog:` — **empty keylog**, reproduced byte-identically at `HEAD~2` |

**EQUIVALENCE GUARDS — labelled, not presented as red-proofs:**

- **case 37**, *"a turn AFTER the submitted prompt IS engagement"* — green in BOTH arms, because the
  pre-change oracle ignores a 4th argument. What it guards is the **over-correction**: a token arm
  that refuses everything, or one whose baseline is off by a record. **Verified by mutation** rather
  than asserted: inserting an unconditional `return 1` into the token arm turns case 37 RED while
  case 36 stays green (run captured; mutant reverted).
- **cases 1, 2, 4–7, 9–11** (the remaining probe cases) are technically red-by-127 on the base tree
  because the file did not exist. They are red-proofs of the file, not of a behaviour change, and
  should be read that way.

**Suites, final state**

| suite | result |
|---|---|
| `tests/lr-fire-resume-submit.bats` (NEW, 21 cases) | **21/21** |
| `tests/handoff-recycle-engagement.bats` (14 → 16) | **16/16** |
| `tests/lr-lib.bats` (the `PY`-core parity pin) | **24/24** |
| `tests/lr-relaunch-bound.bats` | **4/4** |
| `tests/lr-resume-answer-width.bats` · `lr-fire-resume-close-attrib.bats` · `lr-fire-resume-model-ssot.bats` · `handoff-recycle-expect-probe.bats` | **38/38** (after the `LR_RUN` fix — see § 4) |
| `tests/handoff-recycle-remote-resume.bats` · `lr-relaunch-bound.bats` · `lr-lib.bats` | **64/64** |

⚠️ **Two of those runs used `CC_BATS_MAX_ROOTS=0`, recorded to `~/.claude/state/bats-waivers.jsonl`
with the reason**: a 3 h full-tree `bats tests/*` run held both execution roots for the whole
session, and these are the GREEN half of a pair whose RED half is already measured. The land gate is
admission-exempt anyway (memory `the-land-gate-is-admission-exempt`), so this changes nothing about
what the gate will see.

`shellcheck -S warning -x` clean on all three `.sh` files. `bats --count` used on both bats files
after every append.

---

## 3. Deviations from the spec, each with its reason

1. **`INDETERMINATE:submit` is a fifth terminal state**, beside the spec's
   `submitted|queued|FAILED:submit`. An unreadable transcript is not a failed submission and must not
   be recorded as one — the same distinction W2 drew with `INDETERMINATE:boot`, and the same reason.
2. **The probe reports `submitted` in preference to `queued`** when both records exist. The spec does
   not order them; both DO exist for every prompt that lands (a prompt is enqueued, then becomes a
   user record), and reporting the earlier state of a prompt that has already landed would restart
   the wait.
3. **The re-CR is gated on `DRAFT-MINE`, not merely on "a draft".** The spec says "a screen read shows
   the prompt text sitting in the composer"; the screen program therefore compares the composer
   content against the first 40 printable, whitespace-stripped characters of the prompt. A bare
   `DRAFT` is someone else's text and must not be submitted on our behalf.
4. **The screen read and the state append are exported SHELL PROGRAMS, not inline Tcl.** The spec
   says "run `it2 session read` via exec"; doing the box parse in Tcl would have meant spelling an
   awk program as a Tcl string, three quoting layers deep, inside a single-quoted bash string. The
   env-var route makes each one testable on its own — and it was: every verdict was exercised
   standalone before the expect program was touched.
5. **The watcher's token arrives as positional `$16`, resolved in the FOREGROUND** out of the
   launcher, rather than being derived inside the watcher. Same rule `RCY_T0` already follows: the
   watcher must not re-derive a value the relaunch can change underneath it. The 2-occurrence
   precondition (§ 1) lives there too, because only the foreground can see the launcher.
6. **One extra oracle case** (`lr-fire-resume-submit.bats` #21, "a token that never reached the
   transcript is NOT engagement") is in MY file rather than in
   `handoff-recycle-engagement.bats`, so that file is exactly `+2` as specified.
7. **A fifth commit that was not in the brief** — `d43f694a9`, the `LR_RUN` fix. See § 4.

---

## 4. A pre-existing defect found, and why it was fixed rather than only named

`scripts/limit-recover/lr-fire-resume.sh:381` (W2) reads
`CC_ADMIT_BUDGET_KEY="${LR_RUN##*/}"`. A suffix strip is not a default, and under this file's
`set -euo pipefail` an **unset** `LR_RUN` is a fatal error rather than an empty string. Its three
siblings on that same line all carry `:-`.

**Consequence, measured:** every run of the script WITHOUT lr-handoff's launcher — the usage its own
header documents, and the shape the whole `tests/lr-resume-answer-width.bats` WIRING block drives —
died with `LR_RUN: unbound variable` **before expect ever started**. Six tests red, keylog empty, no
menu ever rendered. A launcher run was unaffected because lr-handoff exports `LR_RUN`, which is why
this reached trunk: the surviving path hid the dead one.

I A/B'd it before believing it was mine: the six reds reproduce **byte-identically at `HEAD~2`**
(memory `a-pre-existing-red-is-a-claim-not-a-measurement`). It was fixed rather than merely reported
because the file is W3's to own, the fix is two parameter expansions, and a whole-tree gate
attributes any red suite its diff REACHES to the lander (memory
`gate-attributes-by-reachability-not-causation`). After the fix, a by-hand drive answers the menu
correctly: keylog `DOWN` → `SUBMIT:1:Resume full session as-is`.

---

## 5. Residuals handed to W5 / W7

1. **The token only works once the lr-handoff half lands.** Until `lr-handoff.sh` puts
   `LR_SUBMIT_TOKEN` inside the ingest PROMPT, the arming side's occurrence count sees 1, suppresses
   the token, and prints `⚠ the relaunch prompt does not carry this run's submit token … engagement
   falls back to the WALL-CLOCK oracle`. **That warning line is the arming signal**: W5's
   `bin/cc-lr status` and W7's audit should treat its presence as "the oracle is degraded on this
   run", and its absence as "this run is measured properly". No edit here is needed to arm it.
2. **New state vocabulary to render.** `READY-QUIET`, `READY-NOT-SEEN`, `SUBMIT-RECR`, `submitted`,
   `queued`, `FAILED:submit`, `INDETERMINATE:submit` (stage `inject`/`submit`), plus the
   `recycle-submitted` ledger class in `~/.claude/logs/handoffs.jsonl` with `engaged` ABSENT (not
   false — the question is about submission, not engagement). `FAILED:submit` is re-drivable;
   `READY-NOT-SEEN` and `INDETERMINATE:submit` mean **someone must look**, exactly like `STALE:boot`.
3. **A by-hand resume carries no token and therefore gets no submit verification** — the poll reports
   `skip` and says so. The old screen-phrase loop covered that case badly; nothing covers it now. If
   W5 wants it, the cheapest form is for `lr-fire-resume` to mint its own token when `LR_SUBMIT_TOKEN`
   is unset and append it to `--prompt`, which is a one-line change but changes what the operator
   sees in their own composer.
4. **The screen read needs `it2` and a pane id.** `LR_PANE` comes from `${ITERM_SESSION_ID##*:}`; a
   transplanted or launchd-started pane has neither (memory
   `transplanted-session-loses-dispatch-identity`), and the verdict is then `UNKNOWN` — which parks
   rather than types, i.e. fails in the safe direction, but means the quiet arm cannot rescue a
   missed READY there. W7 should count how often `READY-NOT-SEEN` carries `UNKNOWN` versus `MENU`.
5. **The duplication between the probe and `resume_engaged`'s token scan is deliberate** (two
   consumers, and the `PY` core must stay byte-identical with `lr-lib.sh`), but it is unguarded: no
   test asserts the two agree on one fixture. `tests/lr-lib.bats` shows the shape if W5 wants it.
6. **Not touched, named per the brief:** `tests/lr-resume-answer-width.bats` is the only guard on the
   `LR_RUN` regression and it guards it incidentally. A direct `bash -u` smoke of the by-hand
   invocation would be a better tripwire and belongs with whoever owns that file.
7. **A second, environment-dependent red in that same file — NOT fixed, because the file is not
   mine.** Case 11, *"--summary does NOT suppress the prompt"*, asserts the child saw
   `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=<unset>`. It reads the RUNNER's ambient environment, and
   this session's environment has that variable set to `999999999` — because this very session was
   started by `lr-fire-resume`, whose `export` at `:434` rides into the recovered session for its
   whole life and into every command it ever runs. So the case fails in a recovered pane and passes
   everywhere else. **Proven both ways:** `env -u CLAUDE_CODE_RESUME_THRESHOLD_MINUTES bats -f "does
   NOT suppress" …` ⇒ `ok 1`; without the `env -u`, `not ok 11` with
   `keylog: ENV:CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=999999999`. The `LR_RUN` death was masking it —
   the case never got far enough to read the variable. Two consequences worth someone's attention:
   the fixture needs an explicit `unset` (test-hermeticity), and the export itself is a live instance
   of the D1-safety R1 class W2 named — a launch-time switch that becomes a permanent property of
   the recovered session's environment. It cannot simply be `env -u`'d on the spawn line: reaching
   the child is its entire purpose.
