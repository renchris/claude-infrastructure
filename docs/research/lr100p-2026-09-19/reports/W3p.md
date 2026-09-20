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

---

# W3p hardening — what a 9-hour mutation pass found, and what now kills each survivor

**Appended 2026-09-20, ten commits on `8a9a812cc`** (`691b6f105` was already on the branch when this
pass began; the other nine are this pass). Nothing above this line was changed.

**The headline, in one sentence:** the wave's central feature was **INERT on every run** — the
watcher parsed `${16:-}` for a token the arming side sends as argv **15** — and the suite was
*defending* the defect, because its assertion pinned the wrong constant as its expected value.

**The shape of everything else:** 21 mutants ran against W3p; the ones that died were dying against
cases that EXECUTE the subject, and every one that survived was guarded by a case that reads the
subject's TEXT — a grep for a literal, a grep for a variable name, a grep for a comment — or by a
fixture the parser refuses to read. Nine of this pass's ten commits add no source change at all.

## 1. The defect that made the wave inert, and the guard that protected it

`handoff-fire.sh:6651` read `RCY_SUBMIT_TOKEN="${16:-}"`. `recycle_fire`'s detach line is

```
__recycle·SID·tty·cmdfile·LAUNCH_DIR·old_sid·MARKER·GOAL·prompt·RESUME_CFG·source_sid·T0·SRC_TX·RUN_DIR·TOKEN
```

— fifteen arguments. So `RCY_SUBMIT_TOKEN` was **always empty**: no submit probe ever ran, no
`recycle-submitted` row was ever written, and `resume_engaged` fell back to the wall-clock oracle a
stale notification turn satisfies — the exact hole § 1 above says this wave closes. The feature
shipped dead in the manner
`docs/lessons/an-imported-threshold-can-sit-above-the-model-s-output-range.md` describes.

**And correcting it turned the suite RED**, because `tests/lr-fire-resume-submit.bats:162` asserted
`grep -c 'RCY_SUBMIT_TOKEN="\${16:-}"' == 1`:

```
not ok 1 handoff-fire's resume oracle takes a token and the watcher is handed one
#   `[ "$output" = 1 ] || { echo "watcher does not parse \$16: $output"; false; }' failed
# watcher does not parse $16: 0
```

The expected value **was** the bug (`docs/lessons/stale-assertion-becomes-an-inverted-guard.md`).
Both ends of the wire are now proved by execution instead:

| commit | what it now executes |
|---|---|
| `691b6f105` | the watcher, over the real argv shape, demanding the `SUBMITTED` line and `recycle-submitted` row only the token arm can produce |
| `c65659458` | the real `detach` line, with a recorder in place of `detach`, and the **captured** argv fed to the real watcher — the two ends proved against each other, never each against a constant of its own |

`c65659458`'s red arm (token removed from the detach line) is the measurement that matters:
`691b6f105`'s case stays **green** in it, because a case that hands the watcher an argv the TEST
wrote cannot see the arming end. An index is only ever correct relative to what the other end writes.

## 2. Survivor-by-survivor

| # | what survived 21 mutants | the mutant that now kills it | commit |
|---|---|---|---|
| D2 | `resume_engaged`'s token scan had **one** of its three filters pinned | drop `ts <= t0`; drop `isSidechain` — each alone forges a baseline | `67f9c1bab` |
| D3 | nothing asserted the token reaches the watcher at all | delete `"$RCY_SUBMIT_TOKEN_ARG"` from the detach argv (survived 37/37) | `c65659458` |
| D4 | the 2-occurrence arming gate was never executed | `-lt 2` → `-lt 1` (hand over a token the prompt cannot deliver) | `5c29a0782` |
| D5 | every case passes `RCY_ENGAGE_INTERVAL` as a knob, so its **default** is unguarded | `:-1` → `:-5` (survived 37/37) | `0c3135417` |
| D6 | deviation 3 — the re-CR is gated on `DRAFT-MINE`, not "a draft" | widen to `DRAFT-MINE \|\| DRAFT` and Enter is pressed on a stranger's text | `27ffe3898` |
| D7 | the probe's refusal is pinned; the **consumer's mapping** of it was not | Tcl `lr_probe` returns `none` for an unreadable transcript | `a43c55cc2` |
| D8 | case 18's MENU claim was unreachable *for a fixture reason* | delete the `❯<ordinal>` detector | `7899250f3` |
| D9 | three assertions that could only fail on a doc edit or an indentation change | see § 4 — each measured new-RED / old-GREEN under one mutant | `6180dceb4` |
| D10 | four executed-expect cases with no load discipline | see § 3 — the cause was not load | `54de05d84` |

Two of these are worth their own paragraph.

**D5 is counted, never grepped.** The default is not a tuning — it is the QUANTUM of `rcy_t`, the one
number the `recycle-engaged` row carries about how long engagement took. The case drives the real
watcher through a **symlinked `$0`**: the probe resolves as `$(dirname "$0")/limit-recover/…`, so a
symlink re-points that one sibling at a counting stub while `HF_DIR` (which resolves the link) keeps
every other sibling on the real tree. `docs/lessons/symlinked-0-splits-sibling-sources.md`, used
deliberately. 4 s of window at one poll a second = 4 polls; at five seconds a poll it is 1.

**D8 was a fixture defect, not a missing assertion**, and the difference is provable. The old menu
fixture had no U+2500 border runs, so the awk box parse exited 9 and the verdict was `UNKNOWN`
whether or not the detector existed — both park, both print `READY NEVER SEEN`, both record
`READY-NOT-SEEN`. Measured standalone on the extracted `LR_SCREEN_SH`, one variable:

```
no box:    detector present MENU · detector deleted UNKNOWN   (both park — the mutant is invisible)
with box:  detector present MENU · detector deleted DRAFT     (the verdict moves)
```

The assertion **could not have been written** against a screen the parser refuses to read. The
fixture is now the box the TUI actually paints, and the verdict is asserted in both places `$sv` is
written — the operator-facing line and the state log's `detail`, since `READY-NOT-SEEN` is the same
word for `MENU`, `DRAFT` and `UNKNOWN`.

## 3. D10 — the four expect cases were decided by bats' stdin, not by load

The brief called this load fragility. It is not, and the correction is worth more than the fix.

The program ends **every** path at `interact` — an `exit` there closes the master pty and kills the
resumed session, which is the husk this project exists to prevent, and case 14 pins that count at 0.
`interact` returns only on **EOF of stdin**. So under bats these cases terminated if and only if
whatever stdin the runner happened to be invoked with was already at EOF. Measured this session, one
case, one variable:

```
ELAPSED=242s STATUS=124   (outer bound 240 s, no redirect)
ELAPSED=70s  STATUS=0     (identical case, stdin </dev/null)
```

and in the 242 s arm **every behavioural assertion was already satisfied in the captured output** —
the refusal line, the keylog, the state. It failed at `[ "$status" -eq 0 ]`, before any of them ran.
That is the whole of the reported *"green 4/4 in isolation, 16 reds across three contended runs"*
signature: the verdict was a property of the invocation, and no bound could have fixed it.

`</dev/null` is the cure and it is load-invariant. The **residual** — the program's own wall clock, a
quiet arm plus a 1 s poll loop with an `exec` per tick — is then banded the way `tests/cc-lr.bats`
was banded in `1b2676f4c`: the outer bound is SCALED by measured load/core, the elapsed time is
printed on every run, and a kill is JUDGED only below 1.0/core — above that line it skips with the
number, because a timeout there says nothing about the subject.

`tests/handoff-recycle-engagement.bats` gets the same discipline **where it applies and no more**:
its one SUCCESS window is scaled and the load is printed on every watcher case so a red there is
attributable. Its dead-path windows are deliberately left alone — there the budget only decides how
long the watcher waits before giving up — and it has no outer `timeout` anywhere, so unlike the
expect block its cases can be slow but can never be killed mid-assertion.

## 4. D9 — three assertions replaced, each measured BOTH ways

The evidence that a replacement was *needed* rather than merely different is the same mutant run
against both forms:

| replaced | mutant | new form | old form |
|---|---|---|---|
| case 14 — a `sed -n` span never asserted non-empty | re-indent the anchor by ONE space (invisible in Tcl) | `not ok … the anchor is stale` | `ok 1 OLD form of case 14, verbatim` |
| case 15 — `grep -c LR_PROBE >= 2` under a title claiming two things | `set r [lr_probe $t0]` → `set r {none {}}` | `not ok … the program never executed the probe` | `ok 1 OLD form of case 15, verbatim` |
| case 16 — a verbatim COMMENT grep | the ORACLE drops `isSidechain`, the probe keeps it | `not ok … the probe reads 'none' and resume_engaged's own scan DISAGREES` | `ok 1 OLD form of case 16, verbatim` |

Case 15's title over-claimed by exactly one half: *"never blind-CRs a quiet pty"* was never its to
assert — the mutant that made the quiet arm type unconditionally left both of its strings in place
and it stayed green while case 18 died. That half now lives in case 18, on the verdict itself.

Case 16's replacement is the guard **residual § 5 above asked for**: the token scan is written twice
— once in `lr-submit-probe.sh` for the expect poll, once inside `resume_engaged` for the watcher,
because the `PY` core must stay byte-identical with `lr-lib.sh:lr_engaged_after` — and nothing
asserted the two agree. Five fixtures, both implementations, one verdict each. The fifth is the one
nothing else asserts: an **enqueued** prompt is `queued` to the probe and is **not a baseline** to
the oracle.

## 5. Suites and gates, final state

| suite | result |
|---|---|
| `tests/lr-fire-resume-submit.bats` (21 → **27**) | 27/27 |
| `tests/handoff-recycle-engagement.bats` (16 → **18**) | 18/18 |

`shellcheck -S warning -x` clean on `handoff-fire.sh`, `lr-fire-resume.sh`, `lr-submit-probe.sh`;
`scripts/bats-assert-liveness.py` exits 0 on both suites; `bats --count` run before every execution.
Every mutant in this report was applied to a working copy and reverted — `git diff HEAD -- scripts/`
is empty for the nine test-only commits.

## 6. Residuals this pass hands on

1. **`scripts/test-hermeticity-lint.sh tests` is RED on trunk's population, and not from this diff.**
   It names `lr-handoff-launcher-quoting.bats` (AMBIENT + SEAM) and `lr-relaunch-bound.bats` (LEAK +
   AMBIENT + SEAM). Both arrived with W1/W3i (`94c18dcea`) and W2 (`cc424132a`), both are owned by
   other waves, and neither of this pass's two suites is flagged. A whole-tree gate attributes a red
   to whoever lands (`memory gate-attributes-by-reachability-not-causation`), so **whoever lands
   `lr100p/w3p` will be handed this** — it is a two-line fix per suite (fixture `$HOME`, pin the
   three rule-5 seams) but it belongs to the files' owners.
2. **`--separate-stderr` warnings.** Both suites emit `BW02: Using flags on 'run' requires at least
   BATS_VERSION=1.5.0`. Harmless today (bats-core 1.13 honours the flag); a
   `bats_require_minimum_version 1.5.0` at the top of each file would silence it.
3. **The D10 skip is a real abstention, and it should be counted.** Above 1.0 load/core a killed
   expect case now SKIPS rather than reds. On this box that band is the normal state, so a run can
   report `ok` counts that hide N skips. W7's audit should read skips, not just failures — an
   alarm that abstains silently is the `alarm-polarity` failure.
4. **The agreement guard is a cross-check, not full coverage.** Cases 5–7 pin the probe's filters and
   the two new D2 cases pin the oracle's; § 4's fixture set catches drift in EITHER implementation
   with one set of inputs, but it cannot see a change made identically to both.
5. **Untouched, per the brief:** `lr-ingest-verify.sh`, `lr-handoff.sh`'s launcher prompt and
   `tests/lr-handoff-launcher-quoting.bats` belong to `lr100p/w3i`. Residuals 1–7 of the original
   report stand unchanged; residual 5 is now discharged by § 4's third row.

---

# W3p F1–F4 — the second inert cause, and three tests that could not fail

**Appended 2026-09-20, five commits on `48c6313e0`.** Nothing above this line was changed.

**The headline, in one sentence:** the hardening pass fixed the watcher's end of the token wire
(`$16`→`$15`) and the wave was **still inert on every real recycle**, because the ARMING side's
precondition — "the token's value appears TWICE in the launcher" — is a claim about an artifact
that cannot satisfy it.

## 1. F1 — the second inert cause, driven rather than grepped

The gate read the token out of `$RESUME_LAUNCHER`, counted its occurrences, and refused to hand it
over below 2. Run against the launcher **lr-handoff.sh's own generator emits** — its
`INGEST_PROMPT=` line plus its `FIRE_ARGV=(` → `chmod +x "$LAUNCHER"` span, extracted by anchor and
executed:

```
=== THE REAL GENERATED LAUNCHER ===
export LR_SUBMIT_TOKEN=run:aaaabbbb:20260920-101500:1ad26928
exec …/lr-fire-resume.sh next3 … --prompt /limit-recover\ ingest\ …/bundle
=== REAL ARMING BLOCK OVER THE REAL LAUNCHER ===
⚠ the relaunch prompt does not carry this run's submit token (found 1 occurrence(s) in the
  launcher, need the export AND the prompt) — engagement falls back to the WALL-CLOCK oracle,
  which a stale notification turn can satisfy
ARMED_TOKEN=[]
```

**The count is 1 and cannot become 2.** On this branch the prompt is composed at `lr-handoff.sh:469`
and the token minted at `:736`. On `lr100p/w3i` the launcher **decides its prompt at runtime in the
pane**: the fast path takes `lr-ingest-verify`'s last line, and the fail-closed path composes
`… \$LR_SUBMIT_TOKEN` as a *variable reference*. Neither writes the token's VALUE into the file a
second time — verified by generating the w3i launcher the same way: still 1 occurrence. The premise
lived in the gate's own comment and nothing executed it (memory
`checker-population-rests-on-an-untested-belief`).

**The fix is at the chokepoint, which is why it is in W3p's files and not in lr-handoff.sh.** The
token reaches the target transcript iff it is in the text that gets TYPED, and every path — the fast
prompt, the fail-closed fallback, and a by-hand `--prompt` with no launcher at all — ends at
`lr-fire-resume.sh`. It now appends `(submit token: <tok>)` to the prompt it types, **idempotently**
(an upstream append composes instead of doubling) and **appended, never prefixed** (the re-CR's
`DRAFT-MINE` needle is the prompt's first 40 characters). This also discharges the original report's
**residual 3**: a by-hand resume now carries a token and gets submit verification.

The gate then asks the question it needs answered — *will the token be typed* — of the two places
that can answer it, arming if either does:

| | arm | what it reads |
|---|---|---|
| ARM 1 | the launcher's own text carries the token a second time | a statically composed prompt — the pre-F1 test, kept and still executed |
| ARM 2 | the program the launcher EXECS carries `LR_SUBMIT_TOKEN_IN_PROMPT` | the file **the launcher names**, i.e. the LIVE layer, never this worktree's copy |

ARM 2 is the `launcher-runs-the-live-layer` wire `lr-handoff.sh:522` already runs for
`LR_ADMIT_TOKEN`: a launcher must name a durable path, so it execs a live copy that may predate the
append, and arming a token nothing will type convicts every healthy recycle. An exec target the
parse cannot resolve to a readable file degrades and says which — unproven delivery never guesses.

**The acceptance was not a grep.** The case generates the real launcher, runs the real arming block
over it, and then hands the armed token to the **real watcher on the real argv**:

```
# the real launcher holds the token's value 1 time(s)
ok 24 RED-PROOF the arming gate ARMS over the launcher lr-handoff ACTUALLY generates,
      and that token reaches the watcher
```

with `TOKEN=[run:aaaa1111:…]`, `→ SUBMITTED in RECY-PANE`, and a `recycle-submitted` ledger row.
RED with ARM 2 deleted (the shipped predicate restored), and RED on the whole shipped tree.

**Why the previous case could not see it:** it fed the gate
`exec claude-x --model m --prompt "… $TOK"` — a launcher shape lr-handoff has never emitted, with
the token spelled into the prompt by hand. The fixture satisfied the premise by construction
(`docs/lessons/fixture-shape-hides-address-bugs.md`).

**Forward check for the rebase:** the same arming block, run over the launcher `lr100p/w3i`'s
generator emits, arms — `ARMED=[run:aaaa1111:20260919-210200:45816aa1]`. The fix survives the lead's
rebase without an edit.

## 2. F2 — the submission baseline was pinned nowhere

`t0` decides which records count as *after the prompt*. Blank it and every record qualifies — a
previous attempt's identical prompt, a notification turn from before the relaunch, anything the
transplanted transcript already held. Three sites carry it; all three mutants survived every suite.

| site | mutant | survived | what now kills it |
|---|---|---|---|
| `lr-fire-resume.sh:673` | `set t0 ""` | 7/7 | the probe's argv, with t0 bracketed by the test's own clock reads |
| `handoff-fire.sh:7044` | probe call `"$RCY_T0"` → `""` | 22/23/25 | the only token record is OLDER than the baseline |
| `handoff-fire.sh:6645` | `RCY_T0="${12:-}"` → `""` | 3/3 + 18/18 | one stale assistant turn, no token, argv position 12 alone |

The first survived because the case claiming to ask the probe *"about THIS run"* wildcarded the one
field that says which run: `"$CFG $SID "*" $TOK"`. **The title is now true rather than trimmed** —
`before <= t0 <= after` against the test's own `date -u +%FT%T` reads, which is exact (ISO-8601 UTC
is fixed width, so a string compare is a time compare) and load-invariant: a slow box widens the
window, it never moves t0 out of it.

The probe stub had to change too, and the reason generalises: it recorded `"$*"`, which **joins with
spaces, so an EMPTY argument vanishes from the record entirely**. A tab separator does not fix it —
tab is IFS whitespace and `read` collapses a run of them. It records argc plus one argument per line.

## 3. F3 — a killed case was an `ok`

bats renders a skipped case as `ok N <name> # skip <reason>`, so the load band the hardening pass
added counted a **kill as a PASS** to every audit that greps `^ok` — and on this box the >1.0/core
band is the normal state, so a whole run could report all-ok over cases that ran no assertion. The
pass's own residual 3 named this and left it.

Withholding the **wall-clock verdict** never required withholding the **case**, and D10's own
measurement is why: in the 242 s killed arm every behavioural assertion was already satisfied in the
captured output (`run` keeps `$output` across the SIGTERM) and the case failed only on
`[ "$status" -eq 0 ]`. A kill above the band now prints `# ⚠ KILLED …`, does not judge the timing,
and lets the caller's assertions run. A kill that captured **nothing** is a RED that names the
reason — that is not an abstention either.

> **How an auditor counts this suite:** by `^ok` and `^not ok`, with no third category. It emits
> exactly one skip — `expect(1) not installed`, a missing dependency rather than a verdict — and
> none at all from the band.

Proved by running the real helper, extracted from the suite, inside its own bats file over a program
stubbed to outlive the bound. Two inner cases, because the fix has two halves that fail in opposite
directions: a kill that captured nothing must go RED, and a kill that captured its evidence must
still be JUDGED on it rather than waved through.

That inner run needed its own hardening, and it is the same lesson one level down: `bats` on PATH is
the **cc-bats admission wrapper**, so a shed (rc 75) would emit no TAP while exiting in a way a `^ok`
filter reads as "nothing failed" (`docs/lessons/a-gate-refusal-is-not-a-gate-result.md`). The inner
harness now runs with the admission ceiling disabled — it is a two-case file in `$BATS_TEST_TMPDIR`,
not a gate-corpus root — and its **plan line `1..2` is asserted before any verdict is read off the
stream**, so any other refusal is a named red. Verified with the outer waiver and on a plain `bats`
run with none.

## 4. F4 — the guard, and the rationale that did not reproduce

Both unguarded `eval "$(sed -n '/^resume_engaged() {/,/^}/p' …)"` sites now carry
`command -v resume_engaged >/dev/null`, the shape `handoff-recycle-engagement.bats:381` uses.

**The stated rationale did not reproduce and is recorded rather than inherited.** The finding said an
unguarded extraction would make these cases VACUOUS rather than red. Measured — guard removed AND the
anchor re-indented by one space — **both went `not ok`**: rc 127 matches neither the `-eq 0` nor the
`-eq 1` these cases expect. So on today's assertions this is an **equivalence guard**, named as one in
its comment. What it changes today is the message (a named cause instead of a bare rc mismatch plus a
bats `BW01: Command not found` pointing at the `run` line). What it guards against is one `-eq`→`-ne`
edit away in the `agree` helper: any assertion satisfied by a non-zero rc reads 127 as the oracle's
own *"not engaged"* and passes over a function that was never extracted.

## 5. Suites and gates

| suite | result |
|---|---|
| `tests/lr-fire-resume-submit.bats` (27 → **32**) | 32/32 |
| `tests/handoff-recycle-engagement.bats` | 18/18 |

`shellcheck -S warning -x` clean on `handoff-fire.sh`, `lr-fire-resume.sh`, `lr-submit-probe.sh`;
`scripts/bats-assert-liveness.py` exits 0 on both suites (it caught one `A && B && C || {…}` chain in
the rewritten argv check as *and-absorbed*, split into three assertions); `bats --count` before every
run. Two runs used `CC_BATS_MAX_ROOTS=0` with a reason — the land gate is admission-exempt.

`tests/handoff-alarm-records.bats` is red on this branch (pin 6, file has 7); that pin was raised to 7
on trunk in `793b4c118` and resolves on the lead's rebase. Not touched.

## 6. Residuals

1. **`lr-handoff.sh` was NOT edited and does not need to be for the feature to work**, but its
   `LR_SUBMIT_TOKEN` export is now load-bearing in a way its own file does not state: `lr-fire-resume`
   reads it and appends it, and `handoff-fire`'s ARM 2 verifies that append on the live copy. If W3i
   later puts the token into `INGEST_PROMPT` as well, ARM 1 arms first and the append is a no-op — the
   two compose, they do not collide.
2. **The exec-target parse is crude by design.** It takes the first whitespace word of the `exec` line
   and strips backslashes, so a launcher path containing a space degrades rather than arming. That is
   the safe direction and it is announced, but it is a real (if unreachable-today) blind spot: bundles
   live under `$HOME/.claude/…`.
3. **The append changes what the operator sees in their own composer** — the ingest prompt now ends
   `… (submit token: run:…)`. That was flagged as the cost of this route in the original report's
   residual 3; it is paid here deliberately, because the alternative is a feature that does nothing.
4. **F4's finding is refuted, not fixed.** If the verifier's vacuity claim was based on a different
   assertion shape than the one on this branch, that shape is not in these two cases today.
5. **`--separate-stderr` BW02 warnings** remain on both suites (harmless on bats-core 1.13); a
   `bats_require_minimum_version 1.5.0` header would silence them. Unchanged from the prior pass.
