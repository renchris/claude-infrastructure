# A2 — A batch Jev pass over the autonomy stores

**Verdict: SHIP ONE ARM OF THREE, and it is not the arm that carries the payload.**

Of the three axes the brief proposed, **two are disqualified by their own base rates** and the
third — the dead-premise sweep, which is the valuable one — **Jev structurally cannot answer**,
because it is a question about the state of the machine today and Jev sees only row text. The
mechanical sweep that *can* answer it found **4 dead premises in a 20-row hand sample (20%)**, each
killed by a single `git` or `grep`, in a population **no instrument covers by design**. Build that
sweep. Jev's one surviving job is a 115-call boolean pass that separates genuine operator steps
from agent work laundered into the operator's pile — real, worth ~30 rows, and strictly secondary.

---

## 1. Population — measured, not quoted

`~/.claude/autonomy/backlog.jsonl` is **event-sourced**, 22,922 records. The resident memory
`claimed-is-not-open-in-the-backlog-fold` is correct and load-bearing: `claim` is its own event
(4,848 of them), so a raw grep of the file answers nothing. Every count below is from the fold
(`bin/cc-backlog list --json --all`, 3,728 items, ~40 s).

| store | total | live | note |
|---|---|---|---|
| `backlog.jsonl` items | 3,728 | **337 blocked** · 15 open · 1 claimed · 3,375 done | blocked = the operator-owned pile |
| `decisions/` | 264 files | **47 open** (43 class C, 4 class B) | 113 actioned · 76 expired-actioned · 17 vetoed · 5 no status |
| `pending-activation/` | 64 scripts | **20 not `.done`** | 44 carry a `.done` sentinel |

### The 337 blocked rows

| field | count | % |
|---|---|---|
| carries `needs` (the operator-step text) | 337 | 100% |
| carries a `--run` command | 156 | 46% |
| `source == "needs"` | 220 | 65% |
| carries `whyNotNow` (an impossibility CLASS) | **35** | **10%** |
| carries `falsifier` | 30 | 9% |
| carries `conviction` + `receipt` | 31 | 9% |
| **`needs` byte-identical to `title`** | **175** | **52%** |
| cites ≥1 machine-checkable artifact (path/sha/launchd label) | 240 | 71% |
| cites 2–8 candidate artifacts | 138 | 41% |
| trips a standing-refusal tripwire | **58** | **17%** |

**Age** (`firstTs` → 2026-09-21): median **25.6 d**, p75 35.9, p90 44.6, max 62.9. Only 65 of 337
are under a week old; **272 rows (81%) have sat ≥7 days**.

**Text length** (`title`+`needs`+`whyNotNow`): median **884 chars**, p75 1,252, p90 1,798, max
3,594. Refutation (b) — *"rows too short to carry signal"* — **fails**. These rows are dense,
cite `file:line`, and routinely carry a measurement. The 32,000-token state ceiling is never
close to binding; a whole row fits ~5× over.

**Decision packets**: median age 12 d, p90 **62 d**; 26 of 47 carry no `conviction` and 13 carry
fewer than two options — i.e. they were filed before the F2 number rule and would be refused today.
Median packet 1,530 bytes JSON.

### The hole this sits in — stated in the source, not inferred

`bin/cc-premise` already exists and is a good tool: it is *the* premise-decay predicate, called at
claim time, with a coverage ratchet. **Its population excludes exactly this pile.** From
`bin/cc-premise` docstring for `coverage`, verbatim:

> THE POPULATION IS THE RATCHET'S, STATED HERE ONCE so the two cannot drift: live = open OR
> claimed (**blocked rows excluded — they are not in the wave**), minus `source=="needs"` …

Measured: `cc-premise coverage --json` → `{"probeable": 13, "covered": 5, "uncovered": 8}`. **It
speaks for 13 rows. The 337 are not in its denominator.**

The one repair that touches blocked rows, `scripts/thrash-block-recover.sh` (driven from
`scripts/autonomy-sweep.sh`), is scoped by its own comment to rule-B blocks authored by
`cc-backlog-reap` — *"an **operator block** … structurally out of reach."* So the 337 are
uncovered by construction, by two independent tools, both deliberately. This is
`filed-blocker-is-never-revalidated` with a measured denominator.

---

## 2. The 20 hand-labels

Sampled by sorting the 337 on `firstTs` and taking every 17th row (deterministic, age-spread).
Labels: **(a) PREMISE DEAD** · **(b) LAUNDERED** (a step the filer could have driven) ·
**(c) DUP**. Each (a) label is backed by a command I ran, printed below.

| # | id | filed | label | why |
|---|---|---|---|---|
| 1 | `10eb9e8c5d0c` | 07-20 | — | Azure deploy creds + scope choice. Genuine: credential + value fork. |
| 2 | `f65392a49533` | 08-02 | — | "keep or cut the tile sheen" — a taste call. Genuine. |
| 3 | `96fe7b1687a0` | 08-07 | — | Cloud-reconcile leg; explicitly links to another row. Genuine link, not a launder. |
| 4 | `1a4e292830ae` | 08-09 | — | Admission-gate terms; adds a REFUSING term (G2). Genuine value call. |
| 5 | `408427e74888` | 08-11 | **(a) + (c)** | "reconcile `~/.claude/CLAUDE.md` with the repo — they diverge". `diff ~/.claude/CLAUDE.md CLAUDE.global.md` → **IDENTICAL**. Dead. And a duplicate of #15. |
| 6 | `649748653cc5` | 08-16 | — | Ask KPMG HR. Genuine: third party. *(Also trips the refusal bound — §4.)* |
| 7 | `1d11d3104208` | 08-17 | — | Product call on guest autosuggest replay. Genuine. |
| 8 | `9a522a8fa6fb` | 08-20 | **(b)** | A *diagnosis* with a named fix: "watchers are STACKING … fix is likely arm-once-if-not-live". No operator input is required by anything in the row. Drivable agent work in the operator's pile. |
| 9 | `cbd6bf980b1f` | 08-22 | — | REAP-vs-DEFER value fork, A/B-verified. Exemplary filing. |
| 10 | `e9f9bd65a40d` | 08-23 | **(b)** | "6 of 8 tenants emit NO telemetry". `needs` is byte-identical to `title` and names **no operator action at all**. A finding filed as a blocker. |
| 11 | `e2cd5c8c888d` | 08-26 | — | Send 3 staged Outlook drafts. Genuine: irreversible third-party. *(Trips the refusal bound.)* |
| 12 | `bb6edb17d992` | 09-06 | — | Allowlist scope call. Genuine — an agent may never widen its own permissions. |
| 13 | `4959010a5a4e` | 09-08 | — | Restart `fseventsd` (7.04 GB). Genuine-ish (root). Premise is mechanically re-checkable and was not re-checked. |
| 14 | `f8b768eaaebd` | 09-10 | — | Flip `com.claude.desk-invariant` staged→run. `grep launchd/fleet.manifest:155` → still **`staged`**. Premise **LIVE**. Correct filing (C10). |
| 15 | `a0bc4e5ed1cf` | 09-09 | **(a) + (c)** | Same as #5, refiled 29 days later. Dead and duplicate. |
| 16 | `7928d41eb516` | 09-11 | **(a)** | "the shared checkout carries 2 commits NOT on origin/main". `git -C ~/Development/claude-infrastructure rev-list --count origin/main..HEAD` → **0**. Dead. |
| 17 | `8e120d9f7152` | 09-14 | — | Rule on five landed design decisions. Genuine taste. |
| 18 | `0f639c5f7f9c` | 09-15 | **(a)** | "add `mcp__ms365__graph-batch` to the ms365 PreToolUse matcher in every fleet config dir". Present in **all five** config dirs, and confirmed inside an actual `PreToolUse` matcher via `jq`. Dead. |
| 19 | `01cbf0842c09` | 09-17 | — | Realign effort to the SSOT floor across 5 `settings.json`. Genuine C10. |
| 20 | `762df4cd78b5` | 09-19 | — | Create the Vercel AI Gateway key. Genuine: credential. Unset in my env (a subshell — not conclusive). |

### Base rates from the sample

| axis | hand-labelled | extrapolated to 337 |
|---|---|---|
| **(a) premise dead** | **4 / 20 = 20%** | ~67 rows |
| **(b) laundered** | **2 / 20 = 10%** | ~34 rows |
| **(c) duplicate** | 1 pair / 20 = 5% | see below — the fleet-wide measure is far lower |

Neither (a) nor (b) is near 0 or 1. Refutation (a) does not bite on them. **It bites hard on (c).**

---

## 3. Axis-by-axis: two disqualifications and one structural impossibility

### (c) DUPLICATE — **DISQUALIFIED, base rate ≈ 0.6%**

Jaccard ≥ 0.50 over title tokens across all 337 blocked rows: **16 pairs, 14 distinct rows (4.2%)**.
But reading them, **almost all are false positives of the lexical measure**:

```
0.85  861e48eeaec9 / e594b1560a67  collect cloud session session_0129VzLn… || …session_01VbnMqE…
0.83  cd0ba52ad33e / d6416dde4c08  cloud session session_013Kd6J3… blocked on a permission …
```

Five "collect cloud session …" rows and three "cloud session … blocked on a permission" rows are
**five and three genuinely different sessions**. The only token distinguishing them is an opaque
session id that carries no semantic content — so **a Jev boolean would make the identical error, and
for the identical reason.** Genuine duplicates in the whole store: the `CLAUDE.md`-reconcile pair
(#5/#15) and the `8ad5731d6338`/`8c6c8bba09e1` pair (Jaccard 0.97, same title). **2 pairs in 337 ≈
0.6%** — and a free 40-line Jaccard prefilter already surfaces both. Spending ~56,000 pairwise calls
(or 337 calls against a retrieved candidate) on a 0.6% base rate is the inert-by-construction case
the brief names. **Drop it.**

### (b) LAUNDERED `--why-not-now` — **the brief's framing is disqualified; a narrower version survives**

Of the 337, only **35 carry `whyNotNow` at all** (32 `needs-human`, 3 `not-yet-true`). I read all 35
verbatim. They are **excellent** — every one names a real class-C authority surface, a spend call, a
value fork, or an elapsed-time precondition. My hand-label finds **0 clear launderings and 2
arguable** (`2e8228525c94` "raise the fd budget or cut concurrency"; `5b6d6ad886af` "bound it, swap
it, or drop the check" — both name three mechanical options where the filer could have measured
which is right). **Base rate 0–6%. Disqualified.**

And the *reason* is instructive and should be recorded: **`cc-backlog add` already refuses a
`--why-not-now` that does not open with one of the four impossibility classes, and `needs-human`
already requires `--conviction N --receipt R`.** The gate is at the chokepoint and it works. A Jev
audit of this field would be auditing a population the gate already cleaned —
`enforcement-must-live-at-the-chokepoint`, operating as designed.

**But the hole is real and is already diagnosed inside the store itself.** Row `12b4209cb7fc`'s own
`whyNotNow` reads:

> `block --needs` validates only non-emptiness while `add --why-not-now` enforces the four
> impossibility classes, so **281 of 296 blocked rows (94.9%) carry no class**…

That is the population: the **302 rows that entered through `block --needs`**, where nothing was
enforced. My hand-labels found **2/20 = 10%** of them mis-filed (#8, #10) — agent work sitting in the
operator's pile. **~30 rows. This is the one live Jev arm**, and the question is answerable from row
text alone, which is the only kind of question Jev can answer.

Free corroborating signal, no calls needed: **175 of 337 (52%) have `needs` byte-identical to
`title`** — the filer typed one sentence and it landed in both slots, so no distinct operator step was
ever articulated. The **SUSPECT stratum** (`needs == title` AND no `--run` AND no `whyNotNow`) is
**78 rows (23%)**. Both my (b) labels are in it. Use it as the caller-side prior.

### (a) PREMISE DEAD — the valuable axis, and **Jev structurally cannot answer it**

This is the axis worth the most and it is the one the primitive cannot reach. "Is this premise still
true?" is a question about the **state of the machine today**. Jev sees a 900-character string. The
row `0f639c5f7f9c` says *"add `graph-batch` to the ms365 matcher"* — nothing in that text tells you
whether it is there now. I answered it in four seconds with one `jq`. Jev cannot answer it at any
number of calls, at any prompt quality.

**This is refutation (d) — "the useful judgment needs a string back" — arriving in a sharper form:
the useful judgment needs a *tool call* back, which the envelope forbids absolutely.**

What Jev *could* do is **route**: `boolean` — "does this row name a condition a shell command could
look up today?" — and the caller runs the check. That is a real contribution, because 71% of rows
cite an artifact and 41% cite 2–8 of them, so something must pick. But be honest about its size:
a regex over `[\w./-]+\.(sh|json|md|ts|bats|manifest)`, 7–40-hex shas, and `com\.claude\.[\w.-]+`
already lifts the candidates. The residual Jev buys is *which* candidate, on ~138 rows.

**And this must be said plainly: the 20%-dead finding is a deliverable that needs no Jev at all.**
Four rows died to four one-line commands. Two of them (#5, #15) have been demanding an action for
41 and 12 days over files that are byte-identical. Ship the mechanical sweep whether or not the Jev
arm ships.

---

## 4. Is the text safe to send? — **17% must be excluded, by pattern, before any call**

The standing refusal ("our own engineering artifacts only") is **tripped by a real slice of this
store**, and this is the finding most likely to be missed by someone who only reads the schema.
Measured over all 337:

| tripwire | rows |
|---|---|
| credential-ish (`api.?key`, `secret`, `token`, `oauth`, `keychain`, `password`, `vck_`, `ssh key`) | 23 |
| customer / venue (Heist, Insomniac, Vinyl, Church, Key Collection, bottle menu, guest list, door staff) | 16 |
| mailbox / messages (Outlook, drafts, ms365, `chat.db`, third-party email addresses) | 15 |
| personal / finance / address (Montway, Vista Real, roommate, forwarding address, relocation, KPMG, `$N,NNN`) | 9 |
| **distinct rows tripping ≥1** | **58 (17%)** |

Concrete examples from my own 20-row sample: `649748653cc5` is an employment question to KPMG HR;
`e2cd5c8c888d` names a `$1,530` Montway reservation, a forwarding address and a roommate; two
further rows in the store concern Heist bottle prices — **customer data, named in the mission board**.
Open decision packets are worse in one specific way: I read one (`shipland-esc-c661813`) whose
`matched` array embeds **raw diff lines of a credential-detection regex** — harmless in itself, but
it is arbitrary diff content riding in a field nobody inspects before sending.

**The exact bound I would put on what is sent**, and it is a refusal not a filter:

1. **Send `title` + `needs` + `whyNotNow` only.** Never `run`, never `evidence`, never `receipt`,
   never a decision packet's `matched[]` — those carry arbitrary command strings and diff text.
2. **Hard cap 3,000 bytes** per row (`CC_JEV_RANK_CAP_B`'s value; p90 is 1,798 so this truncates
   almost nothing).
3. **Drop, never redact, any row matching the four tripwire patterns above.** Report the dropped
   count in the summary so the denominator is honest — a silently filtered population is the
   `zero-claim-must-name-its-excluded-strata` defect.
4. **Refuse the whole run if the tripwire regex fails to compile or matches 0 rows** — 0 matches on
   this store means the pattern broke, not that the store is clean.
5. `pending-activation/` is **out of scope entirely**: those are 6 KB median *shell scripts*, and
   their "is this still needed?" question is `test -f …done` plus one grep of the live hook. No
   judgment is involved and sending executable code is gratuitous.

Sendable, non-tripwire blocked rows: **~279**. Sendable ∩ suspect-stratum: **~65**.

---

## 5. The design, copying `scripts/jev/rank-memory.sh`

Every structural element below is lifted from that file, which is the proven shape:
`--yes` on the command line (consent in shell history, not a prompt a non-TTY cannot deliver) ·
the static `CC_JEV_ZDR` check before the first call · a **one-call preflight** that aborts rather
than grinding through a doomed pass · exponential backoff on `reason == "rate-limited"` ·
a visible `x` per verdict-less call · **abort after 10 consecutive skips** · JSONL out under
`~/.claude/autonomy/` with `mkdir -p` and a `: >> "$OUT"` writability assert · and **it never mutates
its subject** — it writes a report, it does not call `cc-backlog unblock`.

### The decomposed question set — two booleans, one call per row

Both questions are asked in a single spec, exactly as `rank-memory.sh` asks `bite`+`superseded`
together. The literal jq:

```sh
spec="$(jq -n --arg s "$row_text" '{ state:$s, questions:{

  operator_only: { type:"boolean",
    instructions:"The text below was filed by an automated software agent as a step that ONLY a human can perform. Judge whether that is actually true of the step it describes. Judge the STEP, not how well the text is written, and not whether the step is a good idea.",
    criteria:{
      true:"completing this step needs something an unattended program genuinely cannot do - typing a credential or password, clicking in a graphical application, touching hardware, contacting another person, spending money, or choosing between options that differ in what is WANTED rather than in what is CORRECT",
      false:"this is a code change, a file edit, a measurement, an investigation, or a command a program could run by itself - a person is not required, only absent" } },

  names_a_checkable_condition: { type:"boolean",
    instructions:"Does the text assert a specific condition about a named file, commit, branch, process, daemon or setting - a condition that a shell command could look up right now to find out whether it is still true? Judge only whether such a lookup EXISTS, not whether the condition is true.",
    criteria:{
      true:"it names a concrete artifact and claims something about its present state, such as a file containing or lacking a string, a commit being absent from a branch, a daemon not being loaded, or a setting holding a particular value",
      false:"it asks for a judgement, a preference, a policy ruling, a message to a person, or a decision about what should be done - there is no fact a command could look up" } }
}}')"
```

**Why two booleans and not a `choice`.** Our one real 140-call Jev run on this box
(`~/.claude/autonomy/jev-rank-20260921T050814Z.jsonl`) measured the `choice` primitive collapsing:
**118 of 140 (84%) landed on one key**, one row got the extreme. A choice over subjective frequency
labels carried almost no discrimination here. The `boolean` in the same run did spread —
min 0.08, max 0.89 — so it is the primitive with signal.

### The caller-side rule

```
  L = p(operator_only)          # low  => looks like agent work
  C = p(names_a_checkable_condition)

  LAUNDERED-CANDIDATE   if  L < P25(L over this run)  AND  row in SUSPECT stratum
                            (needs == title  AND  no --run  AND  no whyNotNow)
  ROUTE-TO-PROBE        if  C > P75(C over this run)
                            => caller regex-lifts paths/shas/launchd labels from the row
                               and runs the canned probe per kind:
                                 path  -> test -f, and grep for the row's own quoted token
                                 sha   -> git merge-base --is-ancestor <sha> origin/main
                                 label -> launchctl list | grep -F, and grep the fleet manifest
  everything else       => NO OUTPUT. Silence is the default.
```

🚨 **Thresholds are PERCENTILES of the run's own distribution, never 0.5.** The 140-call run's
boolean had **median 0.27, p90 0.40, and only 2.9% above 0.5**. A 0.5 cut on 279 rows returns ~8
rows and reads as "nothing found"; a p25/p75 cut returns a ranked ~70 and ~70. This is the
`imported-threshold-can-sit-above-the-model's-output-range` failure, and we have the local data to
avoid it. Print both distributions in the summary so the cut is auditable.

**The report never closes a row.** It emits three lists for a human read: DEAD (probe returned
"condition no longer holds" — with the command and its output), LAUNDERED-CANDIDATE, and
PROBE-CAPABLE-BUT-UNRESOLVED. `cc-backlog unblock`/`done` stays a human verb, for the same reason
`rank-memory.sh` refuses to evict: a wrong close is invisible until the day the row mattered.

### Call budget and wall clock

| pass | rows sent | calls | wall clock @ 6/min + 3 s gap |
|---|---|---|---|
| preflight | — | 1 | 2 s (aborts here if the route is dead) |
| blocked rows, tripwire-filtered | 279 | 279 | **~47–90 min** |
| narrowed to the suspect ∩ sendable stratum | 65 | 65 | **~11–22 min** |
| open decision packets (`what_plain` + `options` only) | 47 | 47 | ~8–16 min |
| **recommended first run** | **65** | **66** | **~15 min** |

Free until **2026-09-25** — four days. A 66-call pilot is ~15 minutes and leaves room to re-run.
Do the 65-row narrowed pass first and read its two distributions before committing 279.

---

## 6. Adversarial pass — the three objections I went looking for

**"You killed 4 premises with grep. Build the grep, not the Jev pass."** Largely correct, and I have
written it that way: the mechanical sweep is the deliverable and the Jev arm is secondary. The
honest residual Jev buys is candidate *selection* on the 138 rows citing 2–8 artifacts, plus the
laundering read that has no mechanical form at all.

**"Something already does this."** Checked directly, not assumed. `cc-premise` exists and is good —
and its `coverage` docstring excludes blocked rows *in its own words*. `thrash-block-recover.sh`
excludes operator blocks *in its own words*. 532 `falsify` events landed in September, but only 30
of 337 blocked rows carry a falsifier and the runner (`_close_falsified`, capped at 5/pass) reads
cc-premise's population, which is the 13. **No tool covers the 337.** Confirmed by reading source,
not by a negative grep.

**"Would Jev actually discriminate?"** The only honest evidence is local and it is a warning: the
`choice` in our one real run collapsed to 84% on one key. I have designed around it (booleans,
percentile thresholds) but **this is a genuine uncertainty and a 65-call pilot must settle it before
a 279-call commitment.** If the `operator_only` boolean comes back with an IQR under ~0.10, the arm
is inert and should be abandoned on the spot — that is the abort criterion.

---

## 7. What its absence would cost

**The mechanical sweep — ship it, unconditionally.** Absent, ~67 rows (20% of 337) go on demanding
an action that is already done. Two of them, verified today, are 41 and 12 days old and ask the
operator to reconcile two files that are byte-identical. These sit in the counted `◆` line of every
close, which means the operator reads a number that is one-fifth wrong, forever, and the error grows
monotonically because nothing in the system can shrink it.

**The Jev laundering arm — ship it narrowed.** Absent, ~30 rows of drivable agent work stay in the
operator's pile wearing an operator label. The operator's own CLAUDE.md calls that the defect the
FILED disposition exists to prevent and measures ~300 closes in 30 days doing it. A ranked list of
the 30 is output whose absence is noticeable.

**Axis (c), duplicates — do not ship.** 0.6% base rate, and the free prefilter already finds both.

**`pending-activation/` — out of scope.** 20 un-`.done` shell scripts whose question is `test -f`.

---

## Re-derive, never re-quote

```sh
bin/cc-backlog list --json --all > /tmp/fold.json          # ~40 s, 3,728 items
jq -r '.[].status' /tmp/fold.json | sort | uniq -c          # the population
bin/cc-premise coverage --json                              # the 13 it speaks for
jq -r '[.[]|select(.status=="blocked" and (.needs//"")==(.title//""))]|length' /tmp/fold.json
git -C ~/Development/claude-infrastructure rev-list --count origin/main..HEAD   # row 7928d41eb516
diff -q ~/.claude/CLAUDE.md ~/Development/claude-infrastructure/CLAUDE.global.md # rows 408427e74888 / a0bc4e5ed1cf
```

All counts measured 2026-09-21. The `done`/`blocked` split moves daily; the 20% dead-premise rate
is a hand-label on 20 rows and carries the sampling error of that n.
