# A01 — Stop-hook timeout decay

Wave: exhaustive-drive, 2026-09-08. Read-only. Every number below carries the command that produced
it and the population it counts.

---

## Answer first

**The premise of this axis is refuted, and the real defect is four times larger than the premise
would have found.** Stop hooks are killed at massive scale — **4,839 measured Stop-hook timeouts in
30 days**, `operator-readout.sh` at **24.2%** of all closes and `completion-assert.sh` at **11.6%** —
but the kill rate is **flat-to-declining in transcript size**: 15.5 per 100 closes below 1 MB, ~26-30
between 1 and 16 MB, 9.4 at 16-32 MB, and **zero above 32 MB**. The transcript is not the variable.

The variable is **`scripts/wrap-ledger.sh`**, the shared ledger dependency that five of the twelve
Stop hooks call. Measured uncached, in the cwds those hooks actually run in: **2.9 s** in a small
worktree, **4.1 s** in `personal`, **12.5 s** in `sevenrooms-bridge`, **14.3 s** in
`claude-infrastructure`, **12.8 s (and 108.6 s on a second sample under load)** in `reso-web-app`.
The Stop budgets are 5 s and 10 s. **One shared dependency exceeds every Stop-hook budget on its own,
in three of five repos, before the hook does any of its own work.** The per-repo kill rate tracks it
exactly: reso-web-app 53.4%, sevenrooms-bridge 46.2%, claude-infrastructure 29.0%, personal 28.7%,
`-worktrees-ci-opaque-id` 0.5%.

And inside `wrap-ledger.sh` the hot term is not git (`git status --porcelain` is 0.02 s in every repo
measured). It is `hooks/lib/dod-path.sh::dod_lineage_ancestors`, a pure-bash BFS that **re-reads
`~/.claude/autonomy/dod/lineage.tsv` once per level, up to 64 levels**, called **twice** per
`wrap-ledger` invocation. Traced: **5,352 `read -r` iterations** over a 445-row file — ~12 full
re-reads — inside a 67,740-line `bash -x` trace whose git calls number **19**.

The failure is silent by construction. Read out of the 2.1.260 binary: the `hook_cancelled` renderer
is `if(w.hookEvent!=="UserPromptSubmit"||!w.timedOut){return null}` — **a timed-out Stop hook prints
nothing**, and the sibling `hook_error_during_execution` case has `if(w.hookEvent==="Stop"||
w.hookEvent==="SubagentStop"){return null}`. Two independent suppressions, both naming Stop. The
hook's output is discarded, the turn ends, and the IDL row is never written either, so the
telemetry that exists to make "didn't fire" distinguishable from "never evaluated" is itself blind
to this.

**Consequence, in the operator's terms: the close-integrity gates fail OPEN, silently, at scale.**
`completion-assert.sh` — the hook whose entire job is to block a false "done" against the live
ledger — is killed before it can speak at 11.6% of closes. `session-continue.sh`'s mechanical-🔧 and
ship-floor blocks are lost at 2.9%.

---

## 1. Registered timeouts (measured)

`~/.claude/settings.json`, `hooks.Stop`, 12 entries, all five config dirs byte-identical on this
matcher (`.claude`, `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary`, `.claude-next` —
each parsed independently; all 12 commands in the same order). Config parity is **not** a source of
coverage loss.

| hook | timeout (s) |
|---|---|
| notify.sh complete | 5 |
| cache-expiry-tracker.sh | 5 |
| teammate-checkpoint.sh | 10 |
| session-continue.sh | 5 |
| anti-deference-nudge.sh | 5 |
| completion-assert.sh | 5 |
| dispatch-assert.sh | 10 |
| boundary-handoff.sh | 5 |
| operator-readout.sh | 10 |
| session-beat.sh stop | 5 |
| goal-inert-watch.sh | 5 |
| cc-permission-beacon.sh clear | 5 |

Binary default when a hook declares none: `var Ef=600000` (600 s). Per-hook resolution:
`timeoutMs: wn.timeout ? wn.timeout*1000 : _` — seconds → ms, exactly as registered.

---

## 2. Size-at-Stop distribution (measured, 30 d, four roots)

Scanner: `scratchpad/a01/scan.py` — streams every `*.jsonl` with mtime within 30 d under the four
realpath-distinct roots (`~/.claude/projects`, `~/.claude-secondary/projects`,
`~/.claude-tertiary/projects`, `~/.claude-quaternary/projects`; `~/.claude-next/projects` is a
symlink to the first and is excluded by realpath). A close = an assistant record carrying a
`"type":"text"` block whose next non-`tool_result` record is a `user` record or EOF; the byte offset
of the end of that assistant line **is** the transcript size at that Stop.

Population: **11,871 closes** across **6,128 files** (7.81 GB).

| | MB |
|---|---|
| p10 | 0.28 |
| p25 | 0.83 |
| **p50** | **2.15** |
| p75 | 4.17 |
| p90 | 6.77 |
| p95 | 9.37 |
| p99 | 17.33 |
| p99.9 | 114.06 |
| max | 229.77 |

Tail mass: ≥10 MB **4.11%** (488) · ≥24 MB **0.59%** (70) · ≥69 MB **0.20%** (24) · ≥150 MB **0.06%** (7).

**Today alone (2026-09-08): 875 main-chain closes, max size-at-close 5.59 MB, p99 5.28 MB.** Not one
of today's closes was on a transcript large enough for any hook's transcript work to matter.

---

## 3. Re-timed latency ladder (measured)

Harness: `scratchpad/a01/time.sh` — synthetic Stop payload on stdin exactly as briefed
(`session_id":"timing-probe-0000"`, `cwd=/Users/chrisren/Development/.worktrees/exhaustive-drive`,
`stop_hook_active:false`), env `ANTIDEF_IDL=/dev/null DISPATCH_ASSERT_IDL=/dev/null
ANTIDEF_STATE_DIR=/tmp/probe-ad DISPATCH_ASSERT_STATE_DIR=/tmp/probe-da`, run from that worktree.
Wall clock via bash `EPOCHREALTIME` (the harness is a bash script — the interactive tool shell is
zsh, where `$EPOCHREALTIME` is empty unless `zmodload zsh/datetime`; two of my first probes returned
`0.00s` for that reason and were discarded).

Worst of 3 reps per cell; load average during the run climbed 21 → 115.

| MB | session-continue (5s) | completion-assert (5s) | anti-def (5s) | dispatch-assert (10s) | operator-readout (10s) | goal-inert (5s) | boundary-handoff (5s) | teammate-ckpt (10s) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2.0 | 1.08 | 0.18 | 0.18 | 0.39 | **11.32** | 0.11 | 0.21 | 0.82 |
| 10.0 | 3.57 | 0.30 | 0.20 | 0.57 | 0.51 | 0.94 | 0.22 | 0.79 |
| 25.1 | 3.86 | 0.55 | 0.31 | 0.81 | 0.57 | 0.48 | 0.19 | 0.92 |
| 52.1 | **5.13** | 4.40 | 0.47 | 1.68 | 0.92 | 0.71 | 0.20 | 0.61 |
| 78.4 | 6.33 | **6.15** | 0.63 | 1.86 | 7.78 | 1.06 | 0.28 | 0.09 |
| 184.0 | 11.16 | 10.38 | 1.47 | 4.25 | 1.87 | 2.64 | 0.40 | 0.08 |
| 229.8 | 20.37 | 6.32 | 3.43 | 8.26 | 3.13 | **31.10** | 0.20 | 0.10 |

Repetition study at the median size (2.0 MB), 12 reps, quieter machine: every hook far under budget —
session-continue med 0.75 s, operator-readout med 1.01 s (min 0.82, max 1.12), completion-assert 0.20,
anti-def 0.17, dispatch 0.36, goal-inert 0.13, boundary 0.22, teammate-ckpt 0.08. **Zero of 96 runs
exceeded a timeout.**

Read the two tables together: the size term is real but crosses budget only at 50-230 MB
(session-continue ~50 MB, completion-assert ~60 MB, goal-inert ~200 MB), which is 0.2-0.3% of closes.
The `11.32 s` for operator-readout at 2.0 MB is the whole story in one cell — that hook blew a 10 s
budget on a *median-sized* transcript, and it is a load/cwd effect, not a size effect.

---

## 4. The direct census: `hook_cancelled` is persisted in the transcript

This replaces every inference above with a count. CC writes an attachment record for each cancelled
hook, and it survives in the transcript:

```json
{"attachment":{"type":"hook_cancelled","hookName":"SessionStart:startup",
  "hookEvent":"SessionStart","command":"~/.claude/hooks/setup-task-symlinks.sh",
  "durationMs":5033,"timedOut":true,"timeoutMs":5000},"type":"attachment", …}
```

`timedOut` is set from `timedOut:!f?.aborted` in the binary — true means *the hook's own timeout*,
false/absent means an outer abort (user interrupt, control-stream close). Scanner:
`scratchpad/a01/cancels.tsv`, same 30-day four-root population, capturing the byte offset (=
transcript size at that moment) alongside each record.

**7,117 `hook_cancelled` records in 30 days.** By event:

| event | timedOut | n |
|---|---|---:|
| **Stop** | **true** | **4,839** |
| SessionStart | true | 964 |
| UserPromptSubmit | true | 480 |
| PostToolUse | (abort) | 299 |
| SessionStart | (abort) | 166 |
| PreToolUse | true | 113 |
| Stop | (abort) | 84 |
| UserPromptSubmit | false | 64 |
| PreToolUse | (abort) | 57 |
| TeammateIdle | true | 15 |
| Stop | false | 8 |

### 4.1 Stop-hook kills by hook, against 11,871 closes

| hook | timeout | kills (30 d) | per 100 closes | size-at-kill p10 / p50 / p90 / p99 / max (MB) |
|---|---:|---:|---:|---|
| **operator-readout.sh** | 10 s | **2,873** | **24.2%** | 0.53 / 2.51 / 7.35 / 11.73 / 48.7 |
| **completion-assert.sh** | 5 s | **1,381** | **11.6%** | 0.79 / 2.47 / 7.75 / 17.16 / 29.3 |
| session-continue.sh | 5 s | 342 | 2.9% | 0.95 / 2.43 / 5.15 / 10.56 / 11.6 |
| boundary-handoff.sh | 5 s | 164 | 1.4% | 2.01 / 3.03 / 5.84 / 10.91 / 11.6 |
| notify.sh complete | 5 s | 34 | 0.3% | 0.75 / 3.08 / 8.53 / 11.56 / 11.6 |
| dispatch-assert.sh | 10 s | 20 | 0.2% | 0.75 / 4.02 / 9.04 / 9.69 / 9.7 |
| teammate-checkpoint.sh | 10 s | 11 | 0.1% | 0.89 / 4.50 / 7.90 / 9.69 / 9.7 |
| anti-deference-nudge.sh | 5 s | 6 | 0.1% | 0.21 / 2.30 / 9.04 / 9.04 / 9.0 |
| goal-inert-watch.sh | 5 s | 5 | 0.04% | 7.06 / 90.84 / 114.06 / 114.06 / 114.1 |
| — *all closes (control)* | — | 11,871 | 100% | 0.28 / 2.15 / 6.77 / 17.33 / 229.8 |

**Every killed hook's size distribution is statistically indistinguishable from the control** — p50
2.4-4.5 MB against the control's 2.15 — except `goal-inert-watch.sh`, whose p50-at-kill is **90.8 MB**
and whose max-at-kill is 114 MB. That one hook, and only that one, is size-bound (its
`grep -a goal_status "$TP"` + `tail -n +N "$TP" | jq` whole-file scan; measured 0.13 s at 2 MB,
31.10 s at 230 MB). It costs 5 kills in 30 days.

### 4.2 Kill rate conditioned on size — the refutation

Kills per 100 closes, `operator-readout.sh`:

| size-at-Stop | closes | kills | per 100 |
|---|---:|---:|---:|
| <1 MB | 3,352 | 521 | 15.5 |
| 1-2 MB | 2,248 | 623 | 27.7 |
| 2-4 MB | 3,137 | 812 | 25.9 |
| 4-8 MB | 2,261 | 687 | 30.4 |
| 8-16 MB | 740 | 220 | 29.7 |
| 16-32 MB | 85 | 8 | **9.4** |
| 32-64 MB | 20 | 2 | 10.0 |
| **64 MB+** | **28** | **0** | **0.0** |

`completion-assert.sh`: 5.9 / 14.2 / 14.4 / 12.4 / 15.5 / 16.5 / **0.0** / **0.0**.
`session-continue.sh`: 1.2 / 4.4 / 4.1 / 2.5 / 2.2 / **0.0** / **0.0** / **0.0**.

The curve is flat then falls off a cliff. A tail-bounded transcript read — the remedy this axis was
commissioned to design — would have moved **0 of 2,873** operator-readout kills and **0 of 1,381**
completion-assert kills.

### 4.3 What the rate DOES track

By project (top strata by close volume):

| project | closes | operator-readout kills | rate |
|---|---:|---:|---:|
| `-worktrees-wt-pool-7` | 93 | 51 | 54.8% |
| `reso-web-app` | 146 | 78 | 53.4% |
| `sevenrooms-bridge` | 344 | 159 | 46.2% |
| `lakehouse-lecture` | 254 | 101 | 39.8% |
| `-worktrees-wt-pool-8` | 234 | 86 | 36.8% |
| **`claude-infrastructure`** | **2,845** | **826** | **29.0%** |
| `personal` | 1,193 | 342 | 28.7% |
| `-worktrees-wt-pool-3` | 453 | 113 | 24.9% |
| `-worktrees-wt-sr-zerohuman` | 381 | 33 | 8.7% |
| `chris-resume` | 270 | 19 | 7.0% |
| `-worktrees-drain-recycle-11` | 362 | 12 | 3.3% |
| `-worktrees-ci-opaque-id` | 221 | 1 | **0.5%** |

A 110× spread across cwds, on the same binary, same settings, same size distribution.

**Machine load is NOT the driver**, and I tested it three ways rather than assuming it. Kill rate
against concurrent-close rate (an independent proxy built from 9,851 timestamped closes, so it cannot
be circular with the kill census):

| closes/min (±60 s window) | closes | opread kills | rate | compl kills | rate |
|---|---:|---:|---:|---:|---:|
| <3/min | 8,052 | 2,825 | **35.1%** | 1,350 | **16.8%** |
| 3-6/min | 1,172 | 21 | 1.8% | 17 | 1.5% |
| 6-12/min | 627 | 27 | 4.3% | 14 | 2.2% |

The correlation is **inverse**. Kills are not bursty either: 4,839 kills spread over **2,956 distinct
minutes** (mean 1.64/min, max 13), with only **10.0%** falling in the 77 minutes carrying ≥5 kills.
This is a pervasive per-close tax, not a load storm.

---

## 5. Root cause: `wrap-ledger.sh`, and inside it, a pure-bash BFS

### 5.1 The consumer set exactly predicts the kill ranking

`grep -ln wrap-ledger hooks/*.sh` → `anti-deference-nudge`, `boundary-handoff`, `completion-assert`,
`operator-readout`, `session-continue` (+ `dod-persist`, `lead-crash-watchdog`, `mailbox-drain`, all
off the Stop path).

| hook | calls wrap-ledger? | gated behind a cheap pre-filter? | kill rate |
|---|---|---|---:|
| operator-readout | yes | only by TTL/continue-armed guards; the heavy `render_block` runs otherwise | 24.2% |
| completion-assert | yes | yes — `abstain "no-close-tell"` at :250 fires before the ledger at :258 | 11.6% |
| session-continue | yes | partly | 2.9% |
| boundary-handoff | yes | partly | 1.4% |
| **anti-deference-nudge** | **yes, but only `if [ "$ship_hold" = 1 ] \|\| [ "$has_done" = 1 ]`** (:288) | **yes, hard** | **0.1%** |
| dispatch-assert | **no** | — | 0.2% |
| goal-inert-watch | **no** | — | 0.04% |

`anti-deference-nudge.sh` is the control that makes this causal rather than correlational: it is the
one wrap-ledger consumer that reaches the ledger only on a lexical tell (450 of 468 evaluations
abstain `no-tell` first, lead-measured), and it has a **0.1%** kill rate against
operator-readout's 24.2%. Same file, same budget, same box.

Note the interaction: completion-assert only reaches the ledger on ~28% of stops
(302 `no-close-tell` abstains of 418 evaluations, lead-measured), yet still records 1,381 kills — so
**conditional on actually running wrap-ledger, its kill rate is ≈41%** (1,381 / (0.28 × 11,871)).

### 5.2 Measured cost of the dependency

`/usr/bin/time -p bash scripts/wrap-ledger.sh --machine`, two consecutive samples per cwd, no
`--transcript` and no `$WRAP_TRANSCRIPT` (this is the **cache-miss** path, and per the script's own
design note the cache key is `(transcript path ⊕ its mtime,size) ⊕ session inputs ⊕ cwd ⊕ env seams`
with **no TTL**, so *"a new turn always appends to the transcript ⇒ new key ⇒ a compute"* —
every Stop is a fresh key and the first consumer to arrive always pays this):

| cwd | run 1 | run 2 | `git status --porcelain` lines |
|---|---:|---:|---:|
| `.worktrees/exhaustive-drive` | 3.10 s | 2.92 s | 1 |
| `personal` | 5.01 s | 4.07 s | 1 |
| `reso-web-app` | 12.75 s | **108.59 s** | 0 |
| `sevenrooms-bridge` | 13.50 s | 12.49 s | 0 |
| `claude-infrastructure` | 14.38 s | 14.27 s | 0 |

Load average 44 → 132 across the run. **The 5 s budget is exceeded in four of five cwds and the 10 s
budget in three, by the shared dependency alone.**

### 5.3 The hot term is not git

`bash -x scripts/wrap-ledger.sh --machine` → **67,740 trace lines**, of which:

- git invocations: **19** (12 `rev-parse`, 5 `status`, 4 `config`, 3 `rev-list`, 1 each
  `symbolic-ref` / `merge-base` / `log` / `diff`)
- `git status --porcelain` measured standalone: **0.02 s** in claude-infrastructure, **0.02 s** in
  reso-web-app, 0.05 s in the worktree

Top repeated trace lines (normalised): `read -r line` ×5,352 · `IFS=` ×5,352 ·
`case "$line" in` ×5,340 · `case "$frontier" in` ×5,340 · `continue` ×5,332.

That loop is `hooks/lib/dod-path.sh:124`, inside `dod_lineage_ancestors`:

```sh
  while [ "$guard" -lt 64 ]; do          # up to 64 BFS levels
    next=""
    while IFS= read -r line || [ -n "$line" ]; do
      …
      case "$frontier" in *"${_DOD_NL}${to}${_DOD_NL}"*) ;; *) continue ;; esac
      case "$seen"     in *"${_DOD_NL}${from}${_DOD_NL}"*) continue ;; esac
      …
    done < "$f"                          # ← the file is RE-READ once per level
    [ -n "$next" ] || break
  done
```

`$f` = `~/.claude/autonomy/dod/lineage.tsv` — **445 rows, 59,960 bytes today**, append-only, one row
per dir-changing succession, growing monotonically with every `--worktree` recycle and every fired
peer. `wrap-ledger.sh` calls `dod_filter_for` **twice** (`:571` and `:582`), and each call runs the
BFS. 5,352 iterations ÷ 445 rows ≈ **12 full re-reads of the file**, in pure bash, with substring
matching against a `$frontier`/`$seen` string that grows as the walk proceeds.

Cost model: **O(rows × depth × 2)** where depth is the cwd's height in the succession graph.
`claude-infrastructure` is the root of most successions, so it sits at maximum depth — which is
precisely why it costs 14.3 s where a leaf worktree costs 2.9 s, with an identical git tree and an
identical `lineage.tsv`. The store only grows; this gets worse every wave.

---

## 6. What the binary does with a timed-out Stop hook (measured, 2.1.260)

Grepped from `/Users/chrisren/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
(198 MB) with a Python byte scanner — the interactive `grep` is rewritten to ugrep by a hook and
`.{0,180}` regexes on a 198 MB binary do not return inside 120 s.

1. **The hook is SIGKILLed and its output is thrown away.** Message string, verbatim:
   `` `${hookName} hook timed out${after Xs} — output discarded. Raise the hook's "timeout" to allow more time.` ``
2. **That message is never shown for a Stop.** Its renderer opens
   `case"hook_cancelled":{if(w.hookEvent!=="UserPromptSubmit"||!w.timedOut){return null}` — **only**
   `UserPromptSubmit` reaches the print.
3. **Hook errors are silenced for Stop too**, independently:
   `case"hook_error_during_execution":{if(w.hookEvent==="Stop"||w.hookEvent==="SubagentStop"){return null}`.
4. **The stop is allowed.** A cancelled hook yields `{outcome:"cancelled", hook:wn}` and contributes
   no `decision`, no `blockingError`, no `additionalContext`. A `decision:"block"` the hook would
   have emitted simply does not exist.
5. **`StopFailure` does NOT fire.** `StopFailure` is a distinct event whose schema is
   `{hook_event_name:"StopFailure", error, error_details?, last_assistant_message?}` — the *turn*
   failing (e.g. `"error":"authentication_failed"`), not a hook timing out. `stop-failure-marker.sh`
   recorded **1** IDL row today against 545 Stop-hook timeouts.
6. **Telemetry goes off-box only.** The cancellation is recorded via `emitHookMetrics` /
   `tengu_repl_hook_finished` (`numCancelled`) to Anthropic's BigQuery endpoint. Nothing local reads
   it. The transcript attachment (§4) is the only local trace, and no shipped tool consumes it.
7. **Stop hooks run concurrently, each with its own budget.** `Ke.map(async function*…)` builds one
   generator per hook and the consumer is `for await (let wn of ‹merge›(Mt))`. Structural read from
   the binary, not timed. Two consequences: (a) the twelve hooks do not share a wall clock, so
   raising one budget does not starve another; (b) the five wrap-ledger consumers all **miss the
   cache simultaneously** — nobody has written it yet — so the memo cannot amortise across them at
   the same Stop, only serialise them behind `WL_LOCK`.

**This is exactly the failure mode the operator's memory index already names.** A "fail-safe" that
matches the healthy output is unfalsifiable
(`fail-safe-default-mimics-the-healthy-state.md`); a guard whose loudness lands only where nobody
reads is a silent retry (`fail-loud-into-a-log-nobody-reads-is-silent.md`). Here both hold at once,
and the IDL — the instrument built to distinguish "didn't fire" from "never evaluated" — is written
at the decision point *inside* the hook, so a killed hook is invisible in the IDL as well.

---

## 7. The 875-vs-469 gap today is fully explained, and it is not timeouts

Two separate accounting questions, both closed.

**(a) The 30-day IDL window.** The IDL holds only from 2026-09-08T08:22Z. Main-chain closes today at
or after 08:22:00Z = **469**. Lead-measured anti-deference-nudge evaluations today = **469**. Exact
identity. The gap against 875 whole-day closes is the rotation boundary, nothing else.

**(b) The per-hook deficits within the window are exactly the measured timeouts.** IDL rows today
(all four accounts write to the one `~/.claude/autonomy/idl.jsonl`; the hooks' path is
`$HOME/.claude/...` hardcoded, so account does not split the store), against transcript-measured
timeouts in the same window (≥09:19:03Z, where these six hooks' rows begin):

| hook | IDL rows | timeouts (transcripts) | rows + timeouts | baseline |
|---|---:|---:|---:|---:|
| goal-inert-watch | 531 | 0 | 531 | — (invocation baseline) |
| **operator-readout** | **392** | **139** | **531** | ✔ exact |
| **completion-assert** | **478** | **54** | **532** | ✔ ±1 |
| **boundary-handoff** | **477** | **52** | **529** | ✔ ±2 |
| dispatch-assert | 493 | 0 | 493 | −38 |
| anti-deference-nudge | 492 | 1 | 493 | −38 |
| session-continue | 672 | 72 | — | n/a (event-driven, not 1-per-invocation) |

Three independent hooks reconcile to the same invocation baseline within 0-2 rows. **The IDL deficit
IS the timeout count.** (`goal-inert-watch` emits >1 row on some invocations, which is why the two
cheapest hooks sit 38 short of its 531 — that residual does not touch the three-way fit.
`session-continue.sh` is excluded because it has five `exit 0` paths with no `log_idl` — `:1078`,
`:1081`, `:1094`, `:1113`, `:1183` — so it is not a one-row-per-invocation hook and its 672 rows are
not comparable.)

Ruled out along the way, each with a measurement rather than an argument:

- **Config-dir drift** — all five `settings.json` register the identical 12 Stop hooks in the
  identical order. Refuted.
- **Sessions on older binaries** — would show as whole sessions missing *all* hooks; instead
  `dispatch-assert` and `goal-inert-watch` are at 100% coverage in **every** session while
  `operator-readout` is bimodal (23 sessions fully covered, 20 fully missing, of 54).
- **A blocking hook cancelling its siblings** — the sharpest candidate, and it is dead: on the 83
  stops where `session-continue` recorded `fired:continue` (the blocking case), `operator-readout`
  logged **100%** of the time.
- **Distinct IDL env vars per hook** (`CC_IDL` for operator-readout/boundary-handoff,
  `COMPLETION_IDL`, `ANTIDEF_IDL`, `DISPATCH_ASSERT_IDL`, `CONTINUE_IDL`) diverting some hooks'
  rows — refuted by the pattern: `boundary-handoff` shares `CC_IDL` with `operator-readout` but has a
  1.4% loss against 24.2%.
- **Transcript size of the affected sessions** — the fully-missing sessions are 1.26, 1.79, 3.15,
  3.34, 4.31 MB; the fully-covered ones are 2.24, 2.56, 2.70 MB. No separation.

---

## 8. Remedies, with the direction each one fails in

Ordered by measured kills removed per unit of effort.

### R1 — Read the lineage store once, not once per BFS level. (S)

`hooks/lib/dod-path.sh:112-142`. Replace the `while [ "$guard" -lt 64 ]` outer loop with a single
pass that builds a `to → from` adjacency map (bash associative array, or one `awk`), then walk it in
memory. Removes ~12 file re-reads × 445 rows × 2 calls from **every** `wrap-ledger` invocation, which
is on the Stop path of five hooks. Expected effect: the 2.9 s floor and the 14.3 s
claude-infrastructure figure both collapse toward the git cost (~0.3 s of 19 calls at 0.02 s each).

**Fails in the direction of**: a rewritten graph walk that resolves a *different* ancestor set would
change which `## … · toplevel=` blocks the frozen DoD keeps, i.e. it could silently widen or narrow
`Scope (frozen)` / `REMAINDER`. Mitigation is mechanical and cheap: the two functions are pure, so
diff the output of old vs new over every toplevel in `lineage.tsv` and require byte-equality before
landing. Do not ship it on the strength of a green suite alone — the suite that certified
`wrap-ledger` cache FAILURE 2 was green while the consumer suite went 3 red.

### R2 — Give every wrap-ledger consumer a cheap pre-filter, copying anti-deference-nudge. (M)

The measured control is already in the tree: `anti-deference-nudge.sh:288` reaches the ledger only
`if [ "$ship_hold" -eq 1 ] || [ "$has_done" -eq 1 ]`, and it is killed 6 times in 30 days where
`operator-readout` is killed 2,873. `operator-readout.sh`'s TTL guards (`stamp-unchanged-ttl`,
`latched-ttl`, 900 s) fire on only ~40 of 392 logged invocations; `continue-armed` carries 215. The
remaining ~135 run the full render.

**Fails in the direction of**: a pre-filter is a *second* predicate in front of the real one, and a
cheap predicate that is not strictly weaker than the expensive one silently shadows it —
`cost-gate-must-be-strictly-weaker.md`. Any pre-filter added here needs its own mutant to prove the
expensive path is still reachable on the cases that matter. This is the recommendation most likely
to trade a loud 24% loss for a quiet, unmeasurable one, which is why it ranks below R1.

### R3 — Make the timeout loss observable. (S)

Nothing on this box reads `hook_cancelled`. A ~40-line reader over the four transcript roots,
emitting one IDL row per Stop-hook timeout (or folding a count into `wrap-ledger`'s output), converts
an invisible 24.2% into a number a close can carry. The scanner in `scratchpad/a01/scan.py` +
`cancels.tsv` is the working prototype.

**Fails in the direction of**: pure detection with no owner is not an actuator
(`detector-with-no-owner-is-not-an-actuator.md`). Ship it attached to something that acts — the
simplest being a `wrap-ledger` term that refuses to render a ✅ certificate on a Stop where
`completion-assert` was killed, since that certificate is currently issued *underneath* a gate that
never ran.

### R4 — Raise `operator-readout` and `completion-assert` budgets as a stopgap. (S)

10 s → 30 s and 5 s → 20 s would recover most of §4.1 immediately, because the p99 uncached
wrap-ledger is ~14 s outside the load tail.

**Fails in the direction of a visibly hung TUI** — a 30 s Stop is 30 s the operator waits with no
output, and (per §6.7) the hooks are parallel, so the *whole* Stop takes the max, not the sum. This
is a bandage, correct only as a same-commit companion to R1, and it should be reverted once R1 lands
rather than left as the fix. It is also the one change that makes the *silent* failure into a *slow*
one, which on this box is strictly better: a slow close is observable.

### R5 — Take the close text from `last_assistant_message` instead of scanning the transcript. (S)

Four hooks each stream the whole transcript through `jq -c` to recover one string:

- `completion-assert.sh:220-225` — `jq -c 'select(.type=="assistant" and (.isSidechain != true)) | …' "$TP" | tail -1`
- `anti-deference-nudge.sh:145-148` — byte-identical filter
- `dispatch-assert.sh:123,132` — two such scans
- `session-continue.sh:267` — the same

The 2.1.260 Stop payload already carries it. From the binary's own schema:
`hook_event_name:k("Stop"), stop_hook_active:O(), last_assistant_message:s().optional().describe(`
**`"Text content of the last assistant message before stopping. Avoids the need to read and parse the transcript file."`**`)`,
computed in `executeStopHooks` from the in-memory message list (`H=U?Er(U.message.content,"\n").trim()`),
never from the file. It is measured-present in this fleet already — `hooks/stop-failure-marker.sh:5`
("measured on 2.1.114 + 2.1.220") and `hooks/subagent-stop.sh:93` reads
`.last_assistant_message` first and calls its absence from the v1 chain the reason every pointer
failed.

**This buys almost nothing on today's kill census** (it removes a term worth ~0.2 s at 2 MB) and I
am ranking it here honestly rather than promoting it because it is elegant. Its real value is
**future-proofing**: it is the one change that makes those four hooks' latency structurally
independent of transcript size, and it deletes ~30 lines of the subtlest code in the tree (the
`jq -c` / `tail -1` dance exists solely because `-r` would let a message's own newlines reach the
stream — `session-continue.sh:238-239`).

**Fails in the direction of**: `last_assistant_message` is `.optional()` in the schema, so a
fallback to the current scan must stay, and the fallback must be reached on *absence*, never on
*empty* — a hook that reads `""` as "no assistant text" and abstains would go silent exactly where it
should speak. Keep the existing `abstain "no-assistant-text"` semantics on the fallback's result, not
on the field's.

### R6 — Tail-bound `goal-inert-watch`'s transcript scan. (S)

`hooks/lib/goal-state.sh:38,84` and `hooks/goal-inert-watch.sh:208-215` do
`grep -a 'goal_status' "$TP" | jq --slurp` and `tail -n +"$((GOAL_LN+1))" "$TP" | jq`. Measured
0.13 s at 2 MB → 31.10 s at 230 MB. A reverse scan of the last N MB, falling back to the full scan
when no `goal_status` is found in the tail, makes it flat.

**Fails in the direction of**: the file's own header states the fail direction that must not move —
every consumer uses `goal_live_condition` to SUPPRESS advice, so a false "no goal" merely restores
old behaviour while a false "goal live" silences a nag. A tail bound that misses an *early* arm
record and finds a later evaluation would read `absent` where the truth is `live` — safe. But
`goal_liveness` counts evaluations **since the last arm**, and a tail bound that clips the arm marker
would report a healthy eval count over a goal armed outside the window: that is the false negative
the function's own comment says it exists to remove. Bound the tail from the arm, not by bytes.
**Worth 5 kills in 30 days** — do it for correctness under growth, not for the census.

### Not recommended

- **Tail-bounded reads in `session-writes.sh`** (`hooks/lib/session-writes.sh:134-146`, a streaming
  `jq -rn 'reduce inputs …'` over the whole file). It is the size term behind completion-assert's
  4.40 s at 52 MB and 10.38 s at 184 MB. But session scope needs *every* write in the file by
  definition, so it cannot be tail-bounded without changing what it answers, and it earns 0 of the
  1,381 measured kills. Leave it.
- **A PostToolUse per-turn cache** for the ledger. `wrap-ledger.sh:220-235` already records that this
  was tried and withdrawn twice, with the general law it produced: *"a cache may never make the
  uncached path worse than uncached, and that is a property of the ARRIVAL PATTERN, not of the hit
  rate"* (measured 72 git vs 60 uncached — 20% worse on the first Stop after any tree change, i.e.
  the common case). Adding a third cache in front of a computation whose hot term is a re-read loop
  is treating the symptom; R1 deletes the term.

---

## 9. Open questions

1. **Why is the kill rate zero above 32 MB?** 28 closes, 0 kills, across every hook. The
   large-transcript sessions are concentrated in `chris-capital-group-contributions{,-ocr-prompts}`,
   which may simply be a cwd where `wrap-ledger` is cheap (shallow lineage, small tree). Untested —
   I did not time `wrap-ledger` in those cwds.
2. **Is the parallel-merge reading of `Klr` correct?** Read structurally from the minified binary
   (`Ke.map(async function*…)` consumed by `for await … of ‹merge›(Mt)`), not timed. If Stop hooks
   are in fact serialised, R4's arithmetic changes and `WL_LOCK` contention becomes the dominant
   term rather than a secondary one. Testable by instrumenting two hooks to stamp start/end epochs.
3. **The 108.59 s `wrap-ledger` sample in `reso-web-app`** (against 12.75 s on the previous run, at
   load 132). A 8.5× tail on one sample is either a load artifact or a distinct pathology in that
   repo. n=2 is not a distribution.
4. **`ENABLE_STOP_REVIEW="0"`** in `~/.claude/settings.json` env — I did not identify what this gates
   in 2.1.260. If it is a *managed* stop-review path it may interact with this chain.
5. **SubagentStop is registered nowhere.** `hooks.SubagentStop` is absent from all five
   `settings.json`. Every subagent close in the fleet is evaluated by zero close-integrity hooks.
   Out of scope for this axis but adjacent to it, and the wave should know.

---

## Appendix — reproduction

All artifacts under
`/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/b418b97a-d3ec-4444-b993-4f29d55f425a/scratchpad/a01/`
(session-scoped; regenerate with the scripts below).

| what | how |
|---|---|
| size-at-Stop census | `scan.py <root> <out.tsv>` ×4 roots → `all.tsv` (11,871 rows) |
| per-close timestamps | `scan2.py <root> <out>` ×4 → `closes-ts.txt` (9,851 rows) |
| timeout census | inline Python over the four roots matching `"hook_cancelled"` → `cancels.tsv` (7,117 rows) |
| latency ladder | `time.sh <transcript>` — bash, `EPOCHREALTIME`; run under bash, never the zsh tool shell |
| wrap-ledger cost | `(cd $repo && /usr/bin/time -p bash scripts/wrap-ledger.sh --machine)` |
| wrap-ledger profile | `bash -x scripts/wrap-ledger.sh --machine 2>trace`; `sed 's/[0-9a-f]\{7,\}/HASH/g' trace \| sort \| uniq -c \| sort -rn` |
| binary strings | Python `re.finditer` over `claude.exe` bytes — not `grep`; the tool shell's `grep` is ugrep and `.{0,180}` on 198 MB does not return |
