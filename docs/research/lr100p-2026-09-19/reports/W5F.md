# W5-F — `hooks/stop-failure-marker.sh` ARM 2: a limit writes its own recovery request

Worktree `/Users/chrisren/Development/.worktrees/wt-lr-w5f`, cut from `origin/main` at `ea5012b30`.
File set: `hooks/stop-failure-marker.sh`, `tests/stop-failure-marker.bats`. Nothing outside it was
touched — verified by `git show --stat` on all four commits.

## 🚨 THE LINE THE LEAD MUST READ BEFORE LANDING

**This arm is unsafe without W5-A's poller policy gate.** It writes one recovery request per cap
death and ~30 sessions die at once on one cap, so a poller that drained them unconditionally would
transplant a whole fleet onto other accounts with no human in the loop. Two things hold that shut:
`requested_by` is the exact literal `stop-failure-marker` (the string W5-A's gate matches), and the
poller kick is gated on `$STATE/autorecover.on`, which **this hook never creates**. Land W5-F with
W5-A — or land it alone only while `autorecover.on` stays absent, in which case the requests are
inert breadcrumbs, the poller meets them on its 600 s `StartInterval`, and W5-A's gate turns them
away. `tests/stop-failure-marker.bats` SB6 and SB16 are the two rows that pin this.

## What I changed

### `hooks/stop-failure-marker.sh` — a new ARM 2, entirely additive

Placed **after** the existing limited arm (beat / page / kick) and **above** the cap early-exit,
for the reason that block already gives about itself: a session whose account has logged 500 deaths
is exactly the one most in need of a recovery request.

| Piece | What it does |
|---|---|
| gate | `case "$ERR" in rate_limit\|rate_limit_error)` — wider than the beat/page arm, deliberately |
| kill switches | `CC_SF_REQUEST=off` · `$LIM/.off` (inherited, whole-arm) · `$LIM/.request-off` (this arm) |
| state root | `_SF_RQ_STATE="${STOP_FAILURE_LR_STATE:-${LR_STATE_DIR:-$HOME/.reso/limit-recover}}"` |
| GC | latches + teammate breadcrumbs expire on the marker's own `$TTL_MIN`, like the page latches |
| skip 1 | teammate — `"agentName"` in the first 8 KB ⇒ `teammate-skip/<sid>` and nothing else |
| skip 2 | handed off — `$(dirname "$TP")/$SID.HANDOFF.json`, beside THIS transcript, never a global path |
| skip 3 | a sid that is absent, `?`, or not path-safe (it goes straight to `lr-fleet --one`) |
| skip 4 | already requested — `[ -e requests-latch/$SID.$DUUID ]` |
| enrichment | ONE bounded `tail -c \| jq` pass ⇒ `death_uuid`, `reset_at_epoch`, `rate_limit_type` |
| publish | `requests/.<sid>.<pid>.tmp` → `mv -f` → `( set -C; : > requests-latch/$SID.$DUUID )` |
| kick | only if `$_SF_RQ_STATE/autorecover.on` exists; bare `kickstart`, no `-k`, no load/unload |

Every path `exit 0`, stdout empty, stderr empty. No python fork, no `ps` walk, no `cc-lr`.

Plus **one pre-existing defect fixed in the same file** — see § Scope grown.

### `tests/stop-failure-marker.bats` — 28 → 52 rows

One new seam in `setup()` (`STOP_FAILURE_LR_STATE`, pointed outside `$HOME` exactly as the suite's
own comment requires of the other four), four helpers, **24 new rows SB1–SB24**, and **both
footprint pins WIDENED, never weakened**:

- `:232 "IT IS NOT A PAGER"` now also asserts a NON-cap death writes **no** request and **no** latch.
- `:440 SA9` now names **six** permitted surfaces (marker, IDL, beat, page-latch, request,
  request-latch) and additionally asserts **no leftover temp file**.

The anti-truncation ANCHOR at `:466` still holds: `grep -c '^@test'` = `bats --count` = 52.

## Verified anchors — every one re-read; the spec's are stale

| Claim | The spec (PLAN_DRAFT.md § W5) | The tree (verified this session) |
|---|---|---|
| insertion point | "`hooks/stop-failure-marker.sh` after `:130`" | `:130` is **mid-statement** — the closing line of the account-resolution `jq` that spans `:125-130`; the `fi` is `:131`. ARM 2 needs `PANE`, which is not resolved until `:156-160`. |
| poller consumer | "`lr-reset-poller.sh:675-679`" | the request loop is **`:671-684`**. `.sid` at **`:674`**; a missing one is renamed `.malformed.json` at **`:675`** — destroyed, never retried. `.target`, `.source_pane`, `.requested_by` at **`:677`**. `rm -f` at `:683`. |
| the enrichment source | "`lr-lib.sh:129-159` `lr_last_api_error`" | `lr_last_api_error` is at **`:174-230`**. `:129-159` is `lr_engaged_after`. |
| "today's four keys" | four | `lr-fleet.sh:885-886` writes **five**: `sid target source_pane requested_by ts`. All five are carried. |
| no launchctl rule | asserted | confirmed — `grep -c launchctl hooks/validate-bash.sh` = **0**. |
| the death-record shape | not given | `quotaLimits:{resetsAt:<epoch>, rateLimitType:"five_hour"\|"seven_day"}`, a **top-level sibling of `message`** — `tests/lr-predicate.bats:166`, `tests/cc-limited.bats:257`, `tests/fixtures/lr-2026-09-19/build.sh:150`. |
| the teammate idiom | `agentName` | `head -c 8000 "$tx" \| grep '"agentName"' >/dev/null` at `handoff-fire.sh:7810`, `lr-fleet.sh:215`, `:238`. `lr_predicate.py:423-427` records that the key lands on line 3–4 and that the substring grep answers YES to `"agentName":null`. |
| the operator flag | `LIMIT_RECOVER_100P:384` | confirmed verbatim at `:384` — 85 %, shipped default OFF. |
| the orphaned item | `LIMIT_RECOVER_100P:408` | confirmed — `:408` hands "the hook's request/page writer" to LIMIT_DETECT_100P. |
| non-cap refusal | — | `lr-fleet.sh:884` `[ "$kind" = limit ] || continue` — the precedent SB5 pins. |

## Where the spec is WRONG, and what the tree made me do instead

**1. The spec tells me to use `lr_last_api_error` AND forbids a python fork. Both cannot hold.**
`lr_last_api_error` (`lr-lib.sh:174-230`) is `tail -c 131072 | /usr/bin/python3`. My brief's
"**No python fork**" is not an opinion either — the subject's own suite states it as measured law at
`tests/stop-failure-marker.bats:521-524`: *"What was REJECTED for cost … a python fork for the cap
…, `oi_origin_class` (3.17 s full-file grep on a 230 MB transcript), `agent_assignee_argv`
(0.19-0.23 s ancestry walk), and reading the tier from the transcript (79 ms)."*

The tree wins, and the arithmetic is one-sided. Measured this session on a 4 MB transcript:

| reader | wall | gives `uuid` | gives `resetsAt` | gives `rateLimitType` |
|---|---|---|---|---|
| `lr_last_api_error` (source lr-lib + python) | **0.05–0.07 s** | yes | **no** | **no** |
| one bounded `tail -c \| jq -Rr` | **0.01 s** | yes | **yes** | **yes** |

So the spec's own route costs 5–7× more and supplies neither of the two fields the request needs —
I would have had to do the jq pass *as well*. I do the jq pass **only**, and do not source
`lr-lib.sh` at all: with both of its transcript readers forbidden here, sourcing it would be
importing a library this arm may not call. Duplication is a stated residual (R1).

**2. `origin_class` and `tier` cannot be derived on this path, and the suite already says so.**
`oi_origin_class` is 3.17 s (it rests on `oi_marker_inbound`, a whole-transcript read) and the
transcript tier read is 79 ms — both named in the rejected list above. I emit `origin_class:
"unknown"` (that lib's own value for *not determined*) and `tier: ""`. The tier is **not** guessed
from the payload's `effort.level`, which is not a tier: `lr-lib.sh`'s header records that a
divergent second spelling of the tier read is what made *"every unattended Fable recovery land on
Opus"*, and the poller re-derives it through lr-lib anyway. An empty key is honest; a wrong one is
the incident.

**3. `CC_SF_REQUEST=off` is the WEAK kill switch, by this file's own reasoning.** `:61-63` says a
file sentinel is used *"because an env var cannot reach a pane that is ALREADY RUNNING, which is the
entire population during a mass cap."* That is exactly this arm's population. I honour
`CC_SF_REQUEST=off` as briefed **and** added `$LIM/.request-off`, plus the inherited `$LIM/.off`.
All three are pinned by SB13 with a positive control.

**4. `requests/.<sid>.tmp` is a shared path and I added `$$`.** Two concurrent re-fires of one sid
interleave into a fixed name and the rename then publishes the result atomically; and any artifact a
killed writer left behind blocks that sid forever, since nothing cleans that directory but the
poller and the poller only removes `*.json`. Still dot-prefixed and still `.tmp`, so the poller's
`"$REQUESTS"/*.json` glob cannot see it either way. SB21 is the row; M15 was the mutant.

**5. SF-j is not mine.** The plan's acceptance list includes *"a request written from the hook
yields `source_retired:1` when replayed through `lr-transplant.sh` under `env -u
CLAUDE_CODE_SESSION_ID` — red today: `lr-transplant.sh:97` skips the rename"*. That is a defect in
`lr-transplant.sh`, outside my file set. **Not fixed, not tested here** — it belongs to whoever owns
`lr-transplant.sh` this wave.

## Scope grown — one pre-existing defect, found here and fixed here

`Scope (grown): + the marker append's stderr leak`

The inherited marker write was `jq … >> "$MARKER" 2>/dev/null || true`. A **failed redirection is
the shell's own message, emitted before `jq` runs**, so the trailing `2>/dev/null` is applied too
late — the exact trap `:211-213` already names for the *input* side. `mkdir -p` exits 0 on a
directory that already exists, so the abstain at `:201` cannot fire for one that is merely
read-only. Reproduced 2026-09-20:

```
$ STOP_FAILURE_MARKER_DIR=<existing, chmod 500> … | bash hooks/stop-failure-marker.sh 2>&1 1>/dev/null
hooks/stop-failure-marker.sh: line 506: …/authentication_failed__next.jsonl: Permission denied
```

That violates the suite's own SILENCE contract (`@test "it emits NOTHING on stderr either"`) on the
death path. Fixed by a group redirect, `{ jq …; } 2>/dev/null`, which is applied to the redirection
too — measured: form `cmd > f 2>/dev/null` LEAKS, form `{ cmd > f; } 2>/dev/null` and
`( cmd > f ) 2>/dev/null` do not. Regression row **SB17**; mutant **M32** dies on it. The same class
appears at the two sites ARM 2 adds (SB15, SB23; mutants M33, M30).

## Mutation score

**35 mutants built · 30 killed · 5 survived**, every survivor an equivalence guard with its own
killing mutation named. Method: swap the subject in place, run the FULL suite, restore, verify by
`sha256` (harness aborts rc 99 on any restore mismatch). Every mutant was confirmed applied before
its run; a no-op mutation reports `NOT-APPLIED` and is not counted.

| # | Arm mutated | Result | Killed by |
|---|---|---|---|
| M1 | `case "$ERR"` gate → `*)` (fire on every death) | KILLED | `:232 IT IS NOT A PAGER`; SB5 |
| M2 | drop the `rate_limit_error` alternative | KILLED | SB4 |
| M3 | drop `CC_SF_REQUEST != off` | KILLED | SB13 |
| M4 | drop `[ ! -e "$LIM/.off" ]` | KILLED | SB13 |
| M5 | drop `[ ! -e "$LIM/.request-off" ]` | KILLED | SB13 |
| M6 | drop the bad-sid guard | KILLED | SB11 |
| M7 | drop the latch/breadcrumb GC | KILLED | SB14 |
| M8 | teammate test always false | KILLED | SB7 |
| M9 | drop the teammate breadcrumb write | KILLED | SB7 |
| M10 | drop the HANDOFF skip | KILLED | SB8 |
| M11 | HANDOFF path → global `$HOME/$SID.HANDOFF.json` | KILLED | SB8 |
| M12 | drop the `[ -e latch ]` idempotence pre-check | KILLED | SB9, SB18 |
| M13 | latch key `$SID.$duuid` → `$SID` (per session, not per death) | KILLED | SB10, SB18 |
| M14 | `duuid` fallback → a constant | KILLED | SB18 |
| M15 | temp name → shared `.$SID.tmp` | **survived pass 1** → KILLED after SB21 | SB21 |
| M16 | `mv -f` → `cp` (non-atomic publish, tmp left) | KILLED | SA9, SB12 |
| M17 | drop `set -C` from the latch (check-then-write) | **survived pass 1** → KILLED after SB22 | SB22 |
| M18 | `requested_by` literal → `sfm-hook` | KILLED | SB1, SB12, SB16 |
| M19 | `target` → `""` | KILLED | SB1 |
| M20 | drop `source_pane` from the record | KILLED | SB1 |
| M21 | drop the `autorecover.on` gate on the kick | KILLED | SA8, SB6 |
| M22 | `kickstart` → `kickstart -k` | KILLED | SB6 |
| M23 | latch create made unconditional | KILLED | SB22 |
| M23b | **latch taken BEFORE the write** (the faithful SF-i mutant) | KILLED | SB6, SB20 |
| M24 | jq `fromjson?` → `fromjson` | **SURVIVED — equivalence guard** | see below |
| M25 | drop `select(type == "object")` | **SURVIVED — equivalence guard** | see below |
| M26 | drop the `objects` guard on `quotaLimits` | **SURVIVED — equivalence guard** | see below |
| M27 | enrichment → the naive `jq -s` slurp | KILLED | SB19 |
| M28 | drop the `timeout` ladder (run the read unbounded) | **SURVIVED — equivalence guard** | see below |
| M29 | `grep '"agentName"'` → `grep -q` | **SURVIVED — equivalence guard** | see below |
| M30 | breadcrumb `( : > f ) 2>/dev/null` → `: > f 2>/dev/null` | **survived pass 1** → KILLED after SB23 | SB23 |
| M31 | `_SF_RQ_STATE` ignores the `STOP_FAILURE_LR_STATE` seam | KILLED (20 rows, incl. SA9's `$HOME` diff) | SA9 + 19 |
| M32 | revert the marker-append braces | KILLED | SB17 |
| M33 | revert the request-write braces | KILLED | SB15 |
| M34 | drop `[ -f "$f" ]` on the transcript | KILLED | SB24 |

### The five survivors, each with the mutation it DOES die on

- **M24 / M25 / M26 — the three jq robustness guards.** Measured directly: `jq -Rr` **recovers per
  input** and continues past a bad line, so removing `fromjson?`, `select(type=="object")` or the
  `objects` guard changes jq's *exit code and stderr*, never its stdout — and jq's stderr is already
  `2>/dev/null` inside the `bash -c`. They are therefore equivalence guards **for output**. Each
  dies on the paired mutation *guard removed AND jq's `2>/dev/null` removed*, which leaks
  `jq: error (at <stdin>:1): Invalid numeric literal …` onto the hook's real stderr — reproduced
  this session. They stay because that pairing is one careless edit away and the guards cost nothing.
- **M28 — the `timeout` ladder on the enrichment.** No test can observe it, because `[ -f "$f" ]`
  (pinned by SB24, mutant M34 dies) already refuses every constructible blocking object — FIFO,
  device, socket. What remains is a *regular file on a stalled mount*, which the harness cannot
  produce. It dies on that, and on nothing a test can build; it is defence in depth behind a guard
  that IS tested.
- **M29 — `grep '"agentName"'` drained vs `grep -q`.** At 8192 bytes the producer's single write
  fits the 64 KiB pipe buffer and completes before the consumer is scheduled, so no SIGPIPE occurs
  and `pipefail` has nothing to promote. `scripts/pipefail-sigpipe-lint.sh`'s own measured table says
  exactly this: `0/1,000 SAFE` below the buffer, `300/300 ALWAYS` at 80,000 B. The mutant dies the
  moment the head bound exceeds 64 KiB — which is why the drained form is kept even though nothing
  here can redden it, and why that lint ratchets the shape repo-wide.

## Death-path cost — interleaved A/B, because an absolute number here would be a fact about the box

The suite's own block warns that a latency bar quoted without the load beside it is *"a fact about
the machine wearing a verdict's clothes"*. This box was at **1-min load 18.5 on 10 cores** (five
sibling waves running their gates), so the armed subject and **pristine `origin/main`** were run in
ONE process with the order flipping every trial, n=12 each, `python3` epoch-ms either side, beat
writer = the real `hooks/session-beat.sh`, osascript + launchctl stubbed, latch dirs cleared each
run (the WINNER path every time), 3.0 MB transcript:

| arm | n | min | median | p92 | max |
|---|---|---|---|---|---|
| **ARMED** `rate_limit` (ARM 2 entered, wins the latch) | 12 | 310 | **327** | 372 | 478 |
| **PRISTINE** `rate_limit` (origin/main, no ARM 2) | 12 | 205 | **230** | 242 | 257 |
| **ARMED** `authentication_failed` (arm NOT entered) | 12 | 129 | **140** | 166 | 175 |
| **PRISTINE** `authentication_failed` | 12 | 116 | **125** | 129 | 130 |

Read off it: **ARM 2 costs +97 ms on the population it is FOR and +15 ms on every other death.**
The +97 ms is ~15 forks (GC `find`, `mkdir`, `head|grep`, the timeout-binary ladder, the bounded
`tail|jq|tail`, `jq -cn`, `mv`, the latch subshell) at this load, and is the same order as the
+90 ms the beat fork already costs on the same population, which W1 accepted.

**The 0.30 s bar is a QUIET-BOX bar and this box is ~1.56× inflated** — the pristine control reads
125 ms here against the 0.08 s the suite recorded quiet. Scaled by that control, the armed arm is
~210 ms, inside the suite's recorded quiet p95 of 0.20 s for arm (ii). **Re-measure on a quiet box
before landing** (R4) — I am not going to launder an inflated reading into a pass.

## Suites

| suite | plan line | result |
|---|---|---|
| `tests/stop-failure-marker.bats` | `1..52` | 52 ok, 0 not ok (52 declared = 52 parsed, the ANCHOR row) |
| `shellcheck -S warning -x hooks/stop-failure-marker.sh tests/stop-failure-marker.bats` | — | clean, rc 0 |
| `bash -n` and `/bin/bash -n hooks/stop-failure-marker.sh` | — | clean (bash 3.2 too) |
| `bash scripts/pipefail-sigpipe-lint.sh` | — | `✓ clean (allowlist honoured)` |
| `python3 scripts/bats-assert-liveness.py` | — | rc 0 (it flagged an and-absorbed line in SB24 on the first run; rewritten as an `if`) |
| `bash scripts/rules-hook-budget-lint.sh` | — | clean, 145 bullets |

`1..52` asserted on every run: a suite that REFUSES emits no `not ok` and exits 0, and this file's
own history is a silent truncation to `1..5`.

## Residuals — each with the command that re-measures it

| # | Residual | Re-measure / act |
|---|---|---|
| **R1** | **The enrichment duplicates a predicate lr-lib should own.** `lr-lib.sh` exists precisely to stop two spellings of one predicate, and this arm now holds a second reader of the death record because W5-A owns `lr-lib.sh` this wave. A follow-up wave should add `lr_death_fields` there (uuid + `resetsAt` + `rateLimitType`, jq not python, so the hook may call it) and have the hook source it. | `grep -n 'quotaLimits' scripts/limit-recover/lr-lib.sh hooks/stop-failure-marker.sh` — two sites today, one after the fix |
| **R2** | **`tier` and `origin_class` ship empty.** Deliberate (§ spec-wrong 2). If a later consumer needs them, they must come from a bounded reader, not from `oi_origin_class` or `lr_tier_from_transcript`. | `jq -r '.tier, .origin_class' ~/.reso/limit-recover/requests/*.json` |
| **R3** | **The `"agentName"` substring test matches `"agentName":null`.** `lr_predicate.py:427` names this. Here it errs toward SKIPPING a session, which is the safe direction, but a real session whose harness wrote a null key is never auto-recovered. | `bash scripts/limit-recover/lr-predicate.sh is-teammate-head <tx>` vs the grep, over a real corpus |
| **R4** | **The cost table above was taken at load 18.5/10 cores.** It is an A/B so the DELTA is sound, but the absolute p92 (372 ms) is not comparable to the suite's quiet-box 0.30 s bar. | `bash /private/tmp/…/scratchpad/costab.sh` (recipe reproduced in this report's § cost) on a box at load < 2/core |
| **R5** | **The plist change is NOT in this diff.** `QueueDirectories` + `ThrottleInterval` remain an operator-owned c10 step. Until it runs, with `autorecover.on` absent the requests accumulate and the poller wakes every 600 s — which is the intended shipped state. | `launchctl print gui/$(id -u)/com.reso.lr-reset-poller \| grep -i 'queue\|interval'` |
| **R6** | **SF-j (`lr-transplant.sh:97` skips the source rename under `env -u CLAUDE_CODE_SESSION_ID`) is unaddressed.** Outside my file set. | `grep -n 'handed-off' scripts/limit-recover/lr-transplant.sh` |
| **R7** | **The timeout-binary ladder is duplicated from `_sf_page`.** Not factored out, because `_sf_page` is inherited law from another wave and a refactor of it would need its own red-proof. Two copies, ~10 lines. | `grep -c 'gtimeout' hooks/stop-failure-marker.sh` — 4 today |

## Commits

Branch `lr100p/w5f`, cut from `ea5012b30`. `scripts/ship-land.sh` was **not** run — the lead lands.
`git diff --stat ea5012b30..HEAD` is exactly three files: the hook, its suite, and this report.

| sha | subject |
|---|---|
| `f40610ed1` | `feat(stop-failure-marker): a limit writes its own recovery request` |
| `f2342566d` | `test(stop-failure-marker): pin the latch fallback and the mid-record tail` |
| `67e4c164c` | `test(stop-failure-marker): kill the two mutants the first pass left alive` |
| `fc831f0c3` | `test(stop-failure-marker): the third redirect site, and a transcript that is not a file` |
| (this doc) | `docs(report): W5F — ARM 2, its mutation score, and where the spec is wrong` |

A `fixup!` for the bats-liveness correction was autosquashed into `fc831f0c3` before delivery
(`GIT_EDITOR=true git rebase --autosquash ea5012b30`); the tree sha was **identical** either side of
the squash, so the history is linear and carries no `fixup!` for the lead to handle.
