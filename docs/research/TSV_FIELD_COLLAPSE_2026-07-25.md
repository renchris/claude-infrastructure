---
status: SWEPT (2026-07-26) — see "Sweep record" at the foot; two sites left to their owning streams
found-by: relogin-build session, 2026-07-25 (surfaced by tm/relogin-sched, verified by lead)
swept-by: cc-backlog 1a941c28a079, worktree wt-1a941c28a079
scope: FINDING + REPRODUCTION (original) · SWEEP + per-site census + regression suite (appended)
severity: silent misparse — wrong data, green tests, no error
corrections: the §"The fix" repro below is WRONG as evidence — see "Correction 1". Its conclusion
  is over-general — see "Correction 2". Both are pinned by tests/tsv-field-collapse.bats §1.
---

# `IFS=$'\t' read` silently shifts fields left when any field is empty

## The defect

Tab is an **IFS-whitespace** character, so `read` collapses a *run* of delimiters into
one. Any empty field therefore does not produce an empty variable — it **shifts every
later field one position left**, silently, with no error and no non-zero status.

## Reproduction (verified this machine, 2026-07-25)

```bash
printf 'acct\tREQUIRED\t\t2026-08-01\t12\tclaude-next\n' \
  | { IFS=$'\t' read -r a b c d e f; echo "c=[$c] d=[$d] e=[$e] f=[$f]"; }
```

```
c=[2026-08-01] d=[12] e=[claude-next] f=[]
```

Expected `c=[]` (the empty field) and `f=[claude-next]`. Instead everything after the
empty field moved left by one.

## Why it is severe, not cosmetic

This is not a display bug — it silently rewrites *meaning*:

- **It bit this build for real.** In the relogin poller, a `launcher` string landed in the
  numeric `k` (live-session count) field. A non-empty `k` reads as "account busy", so the
  poller would have **skipped that account forever, silently**, while its test suite stayed
  green. An account that is never attempted looks identical to an account that needs
  nothing — until the login deadline passes.
- **`bin/cc-blockers` renders the operator's recovery command** from
  `while IFS=$'\t' read -r slug acct model refusal cmd`. Any row with an empty middle
  field (missing `refusal`, absent `account`, no `blocked_model`) shifts `recover_cmd` out
  of its variable — so the operator's one-glance blocker view shows a truncated or wrong
  command. That is a direct defeat of the Silver-Platter rule.

The general shape: **the more nullable the schema, the more often the parse is wrong** —
and it is wrong in a direction that produces plausible-looking values rather than obvious
garbage.

## The fix — sentinel padding, NOT a non-whitespace IFS

The tempting fix is a non-whitespace delimiter. **It does not work on macOS.** Verified on
`/bin/bash` 3.2.57(1)-release (arm64-apple-darwin24):

```bash
printf 'x\001\001y\n' | /bin/bash -c 'IFS=$"\001" read -r p q; echo "p=[$p] q=[$q]"'
# p=[xy] q=[]      <-- did not split at all
```

The working fix is to **guarantee no field is ever empty at the producer**, then strip the
sentinel after the read:

```bash
# producer: give every nullable field a placeholder
jq -r '.[] | [ (.a // "—"), (.b // "—"), (.c // "—") ] | @tsv'

# consumer: read, then un-sentinel
while IFS=$'\t' read -r a b c; do
  [ "$a" = "—" ] && a=""
  ...
done
```

`tm/relogin-sched` applied exactly this (`norm`/`dash` sentinel padding on all four
field-reads) in `bin/cc-relogin-poll`, with a regression test.

## Exposure

**22 other `IFS=$'\t' read` sites across `bin/` and `hooks/`.** Any whose fields can be
empty carry the same latent silent-misparse. Enumerate them with:

```bash
grep -rn "IFS=\$'\\\\t' read" bin/ hooks/
```

For each, the question is only: *can any field ever be empty or null?* If yes, it is
already wrong on those rows.

`bin/cc-blockers` was **fixed in this build** (it is in the relogin team's scope). The
other 21 are untouched.

## Why not fixed here

The Follow-On Gate fails on **boundedness**: 22 sites spread across files that other live
sessions currently hold in their own worktrees. A sweep from this session would collide
with in-flight work and drag unrelated files into a landing whose scope is the relogin
build. Measuring and documenting is cheap and collision-free; the sweep is neither.

## Suggested sequencing

1. Enumerate with the grep above and triage by *nullability of the schema*, not by call
   count — a site with three always-present fields is safe; one reading an optional
   `refusal`/`reason`/`detail` is not.
2. **Fix at the EMITTER, never the reader — and do every column, not the one that broke.**
   The read side is unfixable (a non-whitespace IFS does not split at all on bash 3.2), so
   the only durable fix is guaranteeing non-empty cells at the `@tsv` boundary. Use **one
   shared `cell(ph)` def per script, applied to every column**, rather than a per-field
   patch on whichever field happened to surface the bug:

   ```jq
   def cell(ph): (. // "") | tostring | gsub("[\\t\\r\\n]"; " ")
                 | if . == "" then ph else . end;
   ```

   The `if . == ""` arm is load-bearing: `//` substitutes only for `null`/`false`, so a key
   that is **present but an empty string** still slips through — which is exactly how the
   live `cc-blockers` bug survived a first fix that used `// ""`. Covering every column also
   neutralises embedded tabs/newlines everywhere (a `recover_cmd` containing a tab would
   otherwise split the row), and a single shared def keeps multiple renderers in one script
   from drifting apart.
3. Add a test per site with a deliberately empty middle field. That test fails today.
4. Consider a shared `tsv_read` helper in `lib/` so the sentinel convention is declared
   once rather than re-derived 22 times.

---

# Sweep record — 2026-07-26 (cc-backlog `1a941c28a079`)

Everything above is the original finding, preserved verbatim. Everything below is the sweep
that implemented it, plus two corrections to the finding's own evidence.

## Correction 1 — the §"The fix" repro does not test what it claims

```bash
printf 'x\001\001y\n' | /bin/bash -c 'IFS=$"\001" read -r p q; echo "p=[$p] q=[$q]"'
```

That is `$"…"` — bash **locale-translation** quoting — not `$'…'` ANSI-C quoting. `IFS` was
therefore the four literal characters `\` `0` `0` `1`, which of course never matched the
`\001` bytes in the data. The line proves nothing about non-whitespace separators.

A second trap sits in reading its output. `p=[xy]` is what a **terminal** shows; the actual
bytes are `p=[x\001\001y]` — the whole undivided line, control bytes and all, invisible on
screen. Anyone re-deriving this from the printed output will conclude the wrong thing about
where the field boundary went. Use `od -c`.

## Correction 2 — "a non-whitespace IFS does not work on bash 3.2" is over-general

The conclusion holds for `\001` — but for an unrelated reason, and it does **not** generalise.
Verified on `/bin/bash` 3.2.57(1)-release (arm64-apple-darwin24), reading from a file so no
pipe or quoting layer can be blamed:

| separator | `IFS=$'…' read -r p q r` on `x<S><S>y` | verdict |
|---|---|---|
| `\t` (tab) | `p=[x] q=[y] r=[]` | collapses the run — **the defect** |
| `\001` (SOH) | `p=[x\001\001y] q=[] r=[]` | does not split **at all** |
| `\037` (US) | `p=[x] q=[] r=[y]` | splits once per occurrence, **empty preserved** |

`\001` is special because bash uses it internally as `CTLESC` in its own quoting machinery —
it is not a statement about non-whitespace separators. `\037` works exactly as hoped, and
`bin/cc-board` has depended on that at its telemetry read since before this finding
(`cc-board:77`, with a comment describing this same collapse).

**This matters practically:** on the finding's stated rule, cc-board's working `\037` read
looks like a bug to be "fixed". It is not. Both rows of the table are now pinned by
`tests/tsv-field-collapse.bats` §1 so neither belief can drift.

A third fact worth pinning, also now tested: **jq's `split("\t")` does not collapse runs —
only `read` does.** That is why `hooks/plan-index-update.sh`'s fold and `bin/cc-audit`'s
`--json` branch are correct as written, and why asserting on `--json` cannot detect this bug.

The sweep still used sentinel padding, and the finding's recommendation stands — not because
the read side is unfixable, but because padding keeps `@tsv` (which escapes embedded
tabs/newlines/backslashes inside cells) and needs no change at any consumer that only
displays the value.

## Two padding conventions, chosen per call graph

The one-size answer is wrong. Which sentinel to use follows from what the reader does with
an empty cell:

| convention | when | why |
|---|---|---|
| **visible placeholder** — `cell("?")`, `cell("-")` | operator-facing boards whose reader only *displays* the value | the placeholder is what you would want rendered anyway; no un-pad step to forget. Matches the marker each renderer already uses for unknown, so output is byte-identical for every row that HAS the field |
| **`$'\037'` + un-pad** | data paths where the *emptiness is the signal* (`[ -z "$SUMMARY" ]`, `[ -n "$needs" ]`, a numeric-or-empty pid) | the real `""` has to come back; `\037` cannot occur in an acct, sid, path, ref or command |
| **single space** | an emitter with a consumer this branch must not edit | a space is not in `IFS` here so it holds the column open, and it is inert if never un-padded. Used for `session_index_extract_enriched`, one of whose callers is being rewritten on `fix/infra-perfection` |

One refinement to the finding's `cell(ph)`: use `if . == null then "" else . end`, **not**
`(. // "")`. In jq `false // ""` is `""`, so the published form pads a legitimate boolean
`false` into the placeholder. `bin/cc-value` emits exactly such a column (row freshness).

Pass the sentinel as `--arg pad`, never as a `""` literal in the jq source — the escape
is easy to turn into a **raw** `0x1f` byte in the file, which is invalid inside a JSON string
literal. That happened once during this sweep; `tests/tsv-field-collapse.bats` now fails on
any raw sentinel byte in tracked source.

## Site census — every `IFS=$'\t' read` in `bin/ hooks/ scripts/`

Severity = what the shift actually does, verified, not what it could do in principle.

| site | nullable cell | consequence on `origin/main` | disposition |
|---|---|---|---|
| `bin/cc-decide:180` | `.veto_deadline // ""` (every class-C packet) | **16 OPEN class-C packets** rendered `what_plain` in the 20-char DEADLINE column and blank WHAT — the operator's decision board dropping the decision text | fixed |
| `bin/cc-decide:180` | absent `.status` | class shifted into the status column (3 live `shipland-esc-*` packets) | fixed |
| `bin/cc-backlog:292` | `.project` | title rendered in the PROJECT column; a **blocked** item showed the operator step as its TITLE and lost the `⟵ needs:` marker entirely | fixed |
| `bin/cc-board:90` | `.weekly_pct` etc. | Fable % rendered as the weekly %, FABLE blank → LIMIT state computed off the wrong quota | fixed |
| `bin/cc-value:84` | `.config_dir` (empty on any row that never carried one) | freshness BOOLEAN slid into `$pid`, `$fresh` blank → session counted **inactive** in the value ledger | fixed |
| `bin/cc-context:149` | `.model`, `.cwd`, `.effort` (`// "?"` does not help — `"" // "?"` is `""` in jq) | `cwd` slid into `effort`, cwd column blank | fixed |
| `bin/cc-audit:139` | `.hook` group key | rendered a phantom hook named after its own total, declared HEALTHY, with `abstained=0` for records that were all abstentions | fixed |
| `bin/cc-wave-plan:231` | none (upstream `jq -e 'all(…)'` guarantees non-empty id + enum slot) | none today | padded anyway — the guarantee now lives at the emitter, not 20 lines away in a validation a later edit could relax |
| `hooks/lib/session-index-helpers.sh:385` | **all six** columns `// ""`; `.gitBranch` empty for any non-repo session, `.summary` before one is written | messageCount stored as `created_at`, first prompt as `summary` — corrupting the index `claude-search` reads. **Worst instance found** | fixed |
| `hooks/lib/session-index-helpers.sh` (`extract_enriched`) | assistant text, on any all-tool_use transcript | file list stored as `assistant_text`, commands as `files_changed` | fixed (space pad) |
| `hooks/lib/session-index-helpers.sh:603` | `.category`, `.term` | expansion inserted under the term column | fixed |
| `hooks/plan-index-update.sh:58` | `.value.path` | `firstIndexed` shifted into `$p`; if it happens to name a real file, a plan the entry never named gets indexed | fixed |
| `hooks/session-index-end.sh:59,87` | consumer of the two above | inherits both | fixed (un-pad) |
| `scripts/boot-resume.sh:149` | `.account`, `.name` (absent on many registry entries) | cwd→acct, sid→cwd, name→sid ⇒ `transcript_mtime` called with every argument wrong ⇒ the ghost failed its recency filter and **was never resumed**. A reboot silently dropping the sessions this script exists to bring back | fixed |
| `scripts/limit-recover/lr-select.py:400` | `branch` (last cell), `cwd` under `--allow-missing-cwd` | none reachable today — an empty acct/sid is rejected at parse and a missing cwd is filtered | padded anyway (feeds boot-resume's read) |
| `scripts/idl-abstain-alarm.sh:118` | `.hook` group key | same phantom-hook render as cc-audit; counted in the `hooks=N` summary | fixed |
| `bin/cc-blockers:47` | `.refusal` | the original finding's second example | **left alone** — already fixed on `feat/relogin-observability` (`0dac237`); that stream owns the file |
| `hooks/session-index-sweep.sh:71,158` | consumer of `extract_enriched` | inherits the emitter fix on either branch | **left alone** — `fix/infra-perfection` is rewriting this file and DELETES both reads |
| `scripts/lead-deathwatch.sh:112,134` | — | reads a watch-file and the kqueue helper's output; neither is a jq producer, both fixed-arity | triaged safe |
| `scripts/desk-recycle-invariant.sh:149` | — | `resolve_desk` guarantees all three cells non-empty before printing (cfg falls back to the CC default root; an empty cwd returns 1) | triaged safe |
| `scripts/boot-resume.sh:197` | — | `launchctl list` always emits three columns, `-` not empty, for a missing pid | triaged safe |
| `bin/cc-audit:196,208,219` | — | jq **string interpolation** `"\(.a)\t\(.b)"`, which renders `null` as the four characters `null`, never empty; all three values are `length` results | triaged safe |

## On suggestion 4 (a shared helper in `lib/`) — deliberately NOT done

A sourced `hooks/lib/tsv.sh` would be a **brand-new tracked file**, and `~/.claude/**` are real
directories of per-file symlinks: a new file gets no symlink however current the checkout, so
every `bin/` tool resolving `$HERE/../hooks/lib/tsv.sh` through the live layer would silently
fail to source it and fall back to no padding — re-introducing the bug in exactly the
invisible direction, on the deployed copy only. (Same mechanism as the near-miss recorded in
memory `deploy-lag-checkout-behind-origin`.)

The convention is instead declared once as an **executable guard**, which needs no deployment:
`tests/tsv-field-collapse.bats` §3 enumerates every `IFS=$'\t' read` in `bin/ hooks/ scripts/`
and fails unless each file pads at its emitter, un-pads as a consumer, or appears in a reviewed
exemption table **with a reason**. A companion case fails when an exemption goes stale. That
covers site 25 without a runtime dependency.

**The guard itself needed a guard.** Its sentinel-byte case originally scanned with
`grep -rlP '\x1f' … 2>/dev/null || true`. `-P` is **not portable** — stock BSD `/usr/bin/grep`
on macOS rejects it outright (exit 2) — and the `|| true` folded that error straight into a
PASS. Under any stock-`PATH` invocation the case would therefore report "clean" precisely when
it had never run at all; it passed here only because `grep` on this box happens to be ugrep.
That is this document's own defect one layer up: a silent all-clear, in the direction nobody
checks. It now scans with `git grep`, asserts **exit 1** (ran, matched nothing) rather than
exit 0, and plants a sentinel in a scratch file to prove the scan can still see one — silence
is evidence only once the detector is known live. `git grep` also corrects the scope: the case
claims *tracked* source, and a plain `-r` scan trips over the untracked
`__pycache__/lr-select.cpython-311.pyc`, which legitimately contains a `0x1f` byte. Verified
both directions — RED on a `0x1f` planted in tracked `bin/cc-value`, green once reverted.

## Verification

- `tests/tsv-field-collapse.bats` — 25 cases. **15 of the 20 non-mechanism cases fail on
  `origin/main`** and pass after; the 5 that pass on both (14, 19, 21, 24, 25) are labelled
  in-file as contract / no-regression guards rather than presented as defect regressions.
  Re-measured 2026-07-26 by running the *committed* suite inside a detached `origin/main`
  worktree: 15 fail / 10 pass, the 5 §1 mechanism cases being green on both by construction.
  An earlier "16 of 20 / 4 pass" in this bullet was an off-by-one against that measurement.
- Finding the discriminator was the hard part. A first pass had 12 of 20 green on `origin/main`
  too — i.e. proving nothing, the same failure mode as the repo's 212 dead assertions. Cases
  that looked reasonable but could not fail: asserting on a cell that is **last** in its row
  (cc-backlog `needs`, lr-select `branch`), asserting on `cc-audit --json` (parsed with
  `split("\t")`, already correct), a **substring** grep that matches the shifted row just as
  well (cc-context), and — worst — a test that inlined the *fixed* jq and so only tested
  itself (boot-resume, now driven through the real script's stub seams).
- Every touched tool's output diffed byte-identical to `origin/main` on live data.
- 100/100 pre-existing bats green across `cc-decide`, `cc-backlog`, `cc-audit`, `cc-wave-plan`;
  12/12 `plan-index`; 41/41 `boot-resume` + `lr-select`. `shellcheck -S warning` clean on every
  touched shell file (the two SC2034 and one SC1090 that remain are pre-existing on `origin/main`).

## Out of scope, surfaced

Three `~/.claude/autonomy/decisions/shipland-esc-*.json` packets carry **no `.status` key at
all**. They are invisible to `cc-decide list --open` (whose predicate is `.status == "open"`),
so three parked ship-land escalations never reach the operator's board. Unrelated to this
defect — the padding only made it visible, by rendering `?` where the class used to be. Filed
separately; the fix belongs with `scripts/ship-land.sh`'s packet writer.
