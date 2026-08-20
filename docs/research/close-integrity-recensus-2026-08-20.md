# CLOSE_INTEGRITY efficacy re-census — backlog row `62363cac1e39`

Run 2026-08-20. Subject = the LIVE layer: the shared checkout
`/Users/chrisren/Development/claude-infrastructure` frozen at `9709c99d3` (2026-08-19 04:10), which
`~/.claude/*` per-file symlinks point into. Design doc:
`docs/plans/CLOSE_INTEGRITY_2026-08-10.md`. Baseline it convicted the old design with: **62
content-stranded commits / 21 abandoned-wave branches · 58% of stops assert nothing · 53/60 recent
session-ends voluntary clean exits · deaths 0.34%**.

Every probe was written to a file and run with `bash /tmp/<name>.sh` (the Bash tool here is zsh and
a hook rewrites inline commands). Read-only throughout: `git status --porcelain` in the frozen
checkout read **24** before and **24** after the only executing step (the bats controls) — a
sibling's pre-existing dirt, unchanged by me.

---

## VERDICT TABLE

| | Prediction | Verdict | Number |
|---|---|---|---|
| **P1** | content-stranded commits "well below 62" | **REFUTED as stated · HOLDS on the population it meant** | 60 (sha,branch) pairs = **37 distinct shas**; only **2** are post-land non-fixture |
| **P2** | silent-📦 idles blocked by ship-floor IDL rows | **HOLDS** | **72** fires across **50** distinct sessions, 2026-08-10 → 2026-08-20 |
| **P3** | custody opens/returns balancing | **HOLDS for pane-fired work · REFUTED for the cloud lane** | pane 133 open / 130 discharged (**1** stale, 8.7 d) · cloud **164 open / 45 return** ⇒ 118 open |
| **P4** | D6 fires only at origin terminal closes | **HOLDS empirically, UNMEASURABLE independently** | **30** fires, rung **29 ✅ / 1 👤**, 0 outside {✅,👤}; origin-ness not recorded in any store |

---

## P1 — stranding census — **REFUTED as literally stated**

**Instrument** (the original one, unmodified):

```
cd /Users/chrisren/Development/claude-infrastructure && bash scripts/stranded-sweep.sh main
```

```
✗ stranded-sweep: 60 commit(s) hold content not on origin/main, on 29 of 1822 local branch(es):
  ab-local-1 (1), ab-local-2 (1), claude/fire-20260811T180903Z-57078-1 (2) (+26 more)
```

**60 commits / 29 branches** vs the baseline **62 / 21**. On the headline number the prediction
fails: 60 is not "well below" 62, and the branch count went **up** 21 → 29.

### The headline conflates four populations — and only one of them is the loss class

To name the offenders the default mode suppresses, I ran the SAME script with a **one-line patch**
(a verbatim copy at `/tmp/stranded-verbose.sh`, `diff` = the single deleted damping line
`[[ -z "${MINE}" ]] && return 0`; the `--mine` filter line is untouched and inert while `MINE` is
empty). Every judged commit then prints with its branch, so the count is provably the same 60.

```
bash /tmp/p1c-enum.sh    # copy + 1-line patch + run + per-branch tally
bash /tmp/p1d.sh         # date every sha, partition by branch class
```

Per-branch tally (60 rows):

```
   6 feat/board-runnable-commands      3 ship/backup-2793fa89       1 ship/backup-df9cf269
   5 terminal-arm-land                 3 fix/postland-kill-nonverdict 1 ship/backup-d6100311
   5 ship/backup-088e7c2d              2 wt-63929c8d6072             1 ship/backup-bdc6fa4d
   5 feat/autonomy-100                 2 superseded/wt-97f16b6709fa-duplicate  1 ship/backup-86d789818
   3 terminal-iterm2-vs-kitty-arm      2 ship/backup-f51aae84        1 ship/backup-08de1b9d
   3 ship/backup-a0044e84              2 ship/backup-16611cf59       1 ship/backup-06d2d09e
                                       2 ship/backup-099d40ba        1 probe-conclusion-semantics
                                       2 claude/fire-…57078-1        1 feat/tmux-isid-resolver
                                       1 wt-02ba4e52389a             1 feat/mcp-config-ssot
                                       1 tm/closure-b                1 docs/frontier-problems-2026-07-23
                                       1 claude/fire-…57078-2        1 ab-local-1 · 1 ab-local-2
```

Three corrections the raw 60 hides:

1. **60 is (sha, branch) PAIRS, not commits.** A commit on two branches is counted twice.
   **Distinct shas = 37.** (`cut -f2 /tmp/stranded-dated.tsv | sort -u | wc -l`)
2. **50 of the 60 rows (27 of the 37 shas) predate 2026-08-10** — legacy inventory that no floor
   landed on 2026-08-10 could ever have prevented. Newest of them: 2026-08-09.
   (`awk -F'\t' '{if ($1 < "2026-08-10") pre++; else post++} END{…}' /tmp/stranded-dated.tsv`)
3. **Of the 10 post-land rows, 8 are one deliberate test fixture.** All 2026-08-11, all the same
   `wordfreq` cost-A/B probe content replicated across `ab-local-1`, `ab-local-2`,
   `claude/fire-20260811T180903Z-57078-{1,2}`, `ship/backup-16611cf59`, `ship/backup-86d789818` —
   an A/B probe, not abandoned work.

**Genuinely new, non-fixture stranding since the mechanism landed: 2 commits.**

```
2026-08-15  aed9485e1  feat/mcp-config-ssot         docs(plan): MCP server definitions live in six places…
2026-08-15  b2afc59e6  probe-conclusion-semantics   test(ci): probe run-conclusion semantics for skipped…
```

And **23 of the 60 rows sit on `ship/backup-*` branches** — those are written deliberately by the
land path (`scripts/ship-backup-reap.sh`), i.e. by-design retention, not wave abandonment.

**Honest reading.** The instrument is a **standing inventory**, so it can only ratchet down when
someone reaps branches — it is not a rate. The prediction was written as if it were a rate. On the
quantity it actually meant (new content-stranded work per unit time) the mechanism looks strongly
effective: **2 commits in 10 days**, versus a baseline described as *"62 commits / 21 branches in 5
wave-day spikes."* On the literal words of the prediction it is REFUTED, and the branch count
moving 21 → 29 is a real (if benign) regression driven by `ship/backup-*` accumulation.

**Denominator caveat, stated:** the branch population is now **1822 local branches**; the
2026-08-10 branch total is not recorded anywhere I could find, so "29 of 1822" is **not** directly
comparable to "21 of ?". Treat the branch count as UNMEASURABLE for comparison; the commit count is
comparable because the sweep's rule is unchanged.

---

## P2 — the ship floor — **HOLDS**

**Where it records.** `hooks/session-continue.sh:907` — `log_idl fired "ship-floor" …`. `log_idl`
(`:61-72`) writes TWO stores: a jsonl row to `${CONTINUE_IDL:-$HOME/.claude/autonomy/idl.jsonl}`
**and** a text line to `${CONTINUE_LOG:-$HOME/.claude/logs/session-continue.log}`. There is also a
third, rotation-immune trace: the per-sentinel sidecar `${f}.ship` (`:882`), one file per
(config,cwd) that ever fired.

🚨 **The IDL alone would have produced a false zero.** The live `idl.jsonl` covers **only
2026-08-20T13:02 → 13:53** (7,036 rows, one day) — it rotates every few hours, and the gz archives
reach back only to **2026-08-16T16:21**. A `grep ship-floor` on the live IDL returns **0**, and that
0 is a statement about the file's retention, not about the mechanism. The **CLOG is the
long-retention store** (2026-07-25 → now, unrotated).

```
grep 'reason=ship-floor' ~/.claude/logs/session-continue.log | sed 's/^\[\([0-9-]*\)T.*/\1/' \
  | sort | uniq -c
```

```
  17 2026-08-10      1 2026-08-15      2 2026-08-18
  23 2026-08-11      5 2026-08-16      1 2026-08-19
   5 2026-08-12      3 2026-08-17      5 2026-08-20
  10 2026-08-13
```

- **72 fires total**, across **50 distinct session ids**.
- First fire `2026-08-10T10:10:56Z` — and **no ship-floor line exists anywhere before that date**,
  which is the correct polarity: the arm landed 2026-08-10 and its log starts there, not earlier.
  (The CLOG's own coverage begins 2026-07-25, so the absence is a measured absence, not a gap.)
- Corroborating rotation-immune trace: **13** `~/.claude/state/continue-*.ship` sidecars, mtimes
  2026-08-10 → 2026-08-20.
- Archived IDL rows agree over the window they cover (12 ship-floor rows across the 8 gz archives,
  2026-08-16 → now), so the two stores are consistent.

**Positive control** — the arm can fire on the LIVE bytes, and abstains where it must:

```
cd /Users/chrisren/Development/claude-infrastructure && BATS_TMPDIR=/tmp bats tests/ship-floor.bats
```

**10/10 ok**, including `📦 + own unlanded work ⇒ BLOCKS … and logs arm=ship-floor`,
`🚀 + write evidence ⇒ BLOCKS naming the converger`, and the three negative controls
(`unlanded commits NOT mine ⇒ silent`, `attribution cannot-tell ⇒ silent`, `✅ rung ⇒ silent`).

**Reading.** Fires decayed from 17–23/day in the first two days to 1–5/day — consistent with a
floor that taught the behaviour rather than one that became an always-alarm. Alarm polarity is
healthy: it is not firing on every idle.

---

## P3 — custody balance — **HOLDS for the pane lane, REFUTED for the cloud lane**

Store `~/.claude/autonomy/custody/<cwd-key>.jsonl`, 19 shards, **471 rows spanning
2026-08-10T13:19:12Z → 2026-08-20T13:54:09Z** — full coverage of the window, no rotation.

```
cat ~/.claude/autonomy/custody/*.jsonl | jq -r '.kind' | sort | uniq -c
```

```
 297 open      161 return       13 abandon
```

```
bash ~/.claude/bin/cc-custody count --open      →  123
```

**The 123 open rows split into two populations that must not be summed:**

| Lane | opens | discharges | open now | oldest open |
|---|---|---|---|---|
| **pane-fired** (18 shards, real worktrees) | 133 | 130 | **5** | 2026-08-11T21:32Z |
| **cloud** (1 shard, cwd `/`, `targetPane: cloud:session_…`) | 164 | 45 | **118** | 2026-08-12T03:59Z |

The 5 pane-lane open rows:

```
2026-08-11T21:32:13Z  .worktrees/cloud-pipeline  pane 345→377  slug fire-d56a874d9441   ← 8.7 days old
2026-08-20T12:18:18Z  .worktrees/wt-pool-2       pane  88→459  slug w-measure           ← in flight now
2026-08-20T12:53:24Z  .worktrees/wt-pool-2       pane  88→463  slug w-dead              ← in flight now
2026-08-20T13:13:17Z  .worktrees/wt-pool-2       pane  88→465  slug w-lintcov           ← in flight now
2026-08-20T13:53:19Z  .worktrees/wt-pool-2       pane  88→467  slug w-measure           ← in flight now
```

Per-shard, the pane lane is essentially perfect (`opens=N discharges=N` on 16 of 18 shards; the two
shortfalls are the 2026-08-11 stale row and this session's own live wave). **Exactly one genuinely
undischarged pane row exists in ten days**, and it is 8.7 days old — a real orphan, and the only
one. The custody-v1.1 discharge side (mailbox-drain ping receipt + self-retire restriction lifted)
is demonstrably working.

**The cloud lane is the ledger's accumulating-debt population.** 164 opens, 45 returns → a **27%
discharge rate**, and its rows key on cwd `/` with `originatorPane: "?"`. `cloud-return.sh` does
reference `cc-custody` (`:92`) and 45 cloud returns exist, so the path is **not structurally dead** —
it is leaky. Blast radius is bounded: every consumer reads `--cwd .`, and no ordinary session's cwd
is `/`, so these 118 rows do not fold into anyone's ledger as 🔧. But `cc-custody count --open`
store-wide reads **123**, and any future consumer that drops the `--cwd` scope inherits an
always-alarm.

---

## P4 — D6 fires only at origin terminal closes — **HOLDS empirically; the "non-origin" half is UNMEASURABLE independently**

**Where it records.** `hooks/completion-assert.sh:786` sets `CLASS=shape` when `d6=1`;
`:814` appends `shape` to `arm`; `:815` logs `log_idl fired "false-done" {…arm, class, rung…}` to
`$HOME/.claude/autonomy/idl.jsonl`. A second, independent trace: the per-session latch set
`~/.claude/state/completion-assert/<key>.fired`, whose lines are `<msg-hash> <class>`.
completion-assert has **no** CLOG equivalent.

```
{ cat ~/.claude/autonomy/idl.jsonl; for g in ~/.claude/autonomy/idl.jsonl.2026*.gz; do gzcat "$g"; done; } \
  | grep '"arm":"[^"]*shape' | jq -r '[.ts,.sid,.arm,.class,.rung,(.count|tostring)]|@tsv' | sort
```

- **30 D6 fires**, **18 distinct sessions**, 2026-08-16T20:22 → 2026-08-20T11:10.
- Rung distribution: **29 ✅ · 1 👤**. **Zero** fires on 📦 / 🚀 / ⛔ / 🔧 — i.e. D6 never preempted
  the ledger arm, exactly as `contra == 0` requires.
- Three fires were combination arms (`hedge+shape`, `offer+shape`) — the arm composes as designed.
- Independent corroboration in the latch store: `5 shape` lines across the surviving `.fired` files
  (`awk '{k=($2==""?"assert":$2); n[k]++}' ~/.claude/state/completion-assert/*.fired` → `5 shape,
  28 assert`).

**Coverage limit, stated plainly.** 30 is a **floor, not a total**. The IDL live+archive window
begins **2026-08-16T16:21**, and the `.fired` latches are GC'd at `-mtime +7`
(`completion-assert.sh:762`), with the surviving pre-2026-08-16 files all carrying class-less
`assert` lines. **D6 fires between 2026-08-10 and 2026-08-16 are UNMEASURABLE** — no store retained
them. Nothing about that is a mechanism failure; it is retention.

**Did any fire at a NON-origin close?** **0 by the hook's own predicate** — `:733` requires
`oi_origin_class == origin` before `d6` can be set, and a fired peer or assignee returns
`fired-peer`, so a non-origin shape fire is unreachable in code. **But the IDL record carries no
origin field, no pane and no cwd**, so I cannot re-adjudicate origin-ness from the store. This half
is therefore CONFIRMED-BY-CONSTRUCTION, not measured. What I *can* say from data: all 30 landed on
{✅, 👤}, the only two rungs the design permits.

**Positive control** — the discriminator works in both directions on the live bytes:

```
cd /Users/chrisren/Development/claude-infrastructure && BATS_TMPDIR=/tmp bats -f 'D6' tests/completion-assert.bats
```

**7/7 ok**, including the load-bearing pair:
`D6 FIRE: origin + landed ✅ + real writes + close-tell, shape missing ⇒ block` and
`D6 ABSTAIN: a FIRED PEER (valid stamp for this pane+cwd) is exempt — its close is the ping`.

---

## The fifth number nobody predicted — the silent-close rate went UP

The baseline's load-bearing complication was *"`no-close-tell` is the modal outcome (115/199 = 58%
of adjudicated stops)"*. Re-running that same instrument over every completion-assert record in the
IDL window:

```
{ cat ~/.claude/autonomy/idl.jsonl; for g in ~/.claude/autonomy/idl.jsonl.2026*.gz; do gzcat "$g"; done; } \
  | grep '"hook":"completion-assert"' | jq -r '[.disposition,(.reason|split(":")[0])]|@tsv' | sort | uniq -c | sort -rn
```

```
1008 abstained  no-close-tell     71 abstained  ledger-uncomputable   19 abstained  genuine-blocker
 140 abstained  ledger-clean      54 abstained  capped                 2 abstained  latched-already-fired
  91 fired      false-done        26 abstained  no-assistant-text
```

**1008 / 1411 = 71.4%** of adjudicated stops assert nothing, versus **58%** at baseline. This does
**not** refute the design — D6 sits behind the close-tell gate deliberately, and the silent leak was
assigned to W2b's ship floor, which is firing (P2). But it is the substrate of the felt symptom, and
it is worse than when the design was written.

---

## Does the felt symptom recur, and which residual is the live generator?

**Yes, in one narrow and now-named form — and the live generator is `fd5196ac31ef` (OPEN).**

The other two are genuinely spent:

- `fd517a5863cc` [done] — the SIGKILL/always-alarm sweep damping. Confirmed landed by content: the
  default-mode damping line is present in the live `stranded-sweep.sh:172` and produced exactly the
  one bounded line I quote in P1. Its **successor** item `175bce12e0e1` (2026-08-12, ship-land still
  calls the sweep without `--mine`) is the surviving half, and it is a *reporting* defect, not a
  loss generator.
- `7d6b462a468c` [done] — the trunk-red converge circle. Its symptom is real today (the live layer
  is frozen at `9709c99d3` while trunk is at `dbe3c50c5`), but the row is closed and the successor
  block row `d28f79099ec9` names the converger. It generates **inertness**, not close-integrity
  failures — and P2/P4 both prove the CLOSE_INTEGRITY arms are executing from the frozen layer, so
  it is not this census's generator.

**`fd5196ac31ef` is live, and I ran its own falsifier to prove it.** The row (2026-08-10, review #3)
reads: *"D6 origin oracle: originator of a SAME-CWD self-retire fire reads fired-peer forever
(marker lands in its own transcript via tool_result; by-cwd proof needs stamp.paneUUID==my-pane or
tool_use-record exclusion)"*, with the falsifier recorded verbatim in the store:

```
cd /Users/chrisren/Development/claude-infrastructure && grep -Eq "tool_use|toolUseResult" hooks/lib/origin-identity.sh
→ rc 1, NO MATCH
```

The demanded exclusion is **absent** from the live lib. Mechanism, read out of
`hooks/lib/origin-identity.sh` `oi_origin_class`, `state=absent` branch:

```bash
idxpane="$(read_fired_cwd_index "$dir" "$cwd")"          # by-cwd index finds a candidate peer
… closed == null … && scwd == cwd …                       # peer's stamp still open, same cwd
marker="$(jq -r '.marker' …)"
if grep -qF -- "$marker" "$tp"; then printf 'fired-peer'; fi   # ← the marker is in the ORIGINATOR's
                                                               #   own transcript, as the tool_result
                                                               #   of the fire it just performed
```

So an **origin** session that fired a peer **into its own cwd** classifies itself as `fired-peer`,
and D6 (`:733`) exempts it — the origin Pyramid-close contract silently never fires for exactly the
session it was built for. The comment two lines above even names the negative it defends against
(an operator pane opened in the peer's worktree) — but not this one, because the originator's
transcript is the one place the marker is guaranteed to be.

**Exposure bound, measured, so this is not overstated:** `~/.claude/cc-fired/` holds **629** stamps,
**191** with `closedAt: null`, of which **49** sit on a cwd that still exists. The defect needs a
**same-cwd** fire, and the overwhelming majority of fires target a fresh `wt-*` worktree whose cwd
differs from the originator's — so the by-cwd key misses and the oracle answers `origin` correctly.
The exposed population is the no-`--worktree` fire (e.g. the stamps sitting on `/Users/chrisren`).
Narrow, but it is precisely the shape the operator feels: a lead that fanned work out and then
closed without the two answers.

**Filed-residual verdict:** `fd5196ac31ef` is the live generator; its falsifier is still unmet;
its fix is the one named in its own title (`stamp.paneUUID == my-pane`, or exclude `tool_use` /
`toolUseResult` records from the marker grep).

---

## What I could NOT measure, and why

1. **D6 fires 2026-08-10 → 2026-08-16.** No store retained them (IDL rotates ~4×/day with 8 gz
   archives reaching 2026-08-16T16:21; `.fired` latches GC at `-mtime +7` and the survivors are
   class-less). The 30 I report is a floor over 4 days, not a 10-day total.
2. **Origin-ness of the 30 D6 fires, independently.** The IDL row carries `arm/class/rung/count`
   and no pane, cwd or origin verdict. CONFIRMED-BY-CONSTRUCTION only.
3. **The 2026-08-10 branch-population denominator for P1.** "21 branches" has no recorded total to
   divide by; today's is 1822. The branch-count comparison is not sound; the commit count is.
4. **"53/60 recent session-ends voluntary clean exits" and "deaths 0.34%".** These come from the
   transcript/deaths recon agents whose reports lived in the 2026-08-10 session's scratchpad
   (`scratchpad/recon/report-{transcripts,deaths,census}.md`), which is not on disk in either the
   frozen checkout or this worktree. I did not re-derive them — that is a four-account transcript
   sweep, a different and much larger instrument than the four this row names.

## Probe files (all re-runnable)

```
/tmp/p0-inventory.sh /tmp/p0b.sh   instrument discovery in the frozen checkout
/tmp/p1-stranded.sh                P1 — the unmodified stranded-sweep
/tmp/p1c-enum.sh /tmp/p1d.sh /tmp/p1e-p3e.sh   P1 — 1-line-patched enumeration, dating, partition
/tmp/p2a-schema.sh /tmp/p2b.sh /tmp/p24c.sh /tmp/p24d.sh   P2/P4 — store schemas, coverage, fires
/tmp/p3b.sh /tmp/p3c.sh /tmp/p3d.sh            P3 — custody
/tmp/p-control.sh                  positive controls (ship-floor 10/10, D6 7/7)
/tmp/p5b.sh /tmp/p5d.sh /tmp/p5e.sh /tmp/p5f.sh  residual adjudication + falsifier + exposure bound
```
