# Executed-path fork census — `hooks/validate-bash.sh`

**Date:** 2026-08-17 · **Subject:** `hooks/validate-bash.sh` (1012 lines) + its sourced
`hooks/lib/is-true-flag.sh` · **Harness:** `scripts/hook-fork-census.sh` (re-runnable) ·
**Corpus:** `tests/fixtures/hook-fork-census-corpus.tsv` · **Re-derives:** R-3 of
`docs/plans/HOOK_CHAIN_COST.md` (backlog `8942f3b1506d`).

---

## 1. The finding

**R-3's aggregate is 13% too high while both of the factors underneath it are wrong in opposite
directions — and the file it names is not where a third of the forks live.**

R-3 reads: *"`validate-bash.sh` performs **12 `grep` forks** … | ~42 ms"*. Measured on the path a
real invocation actually takes, at the same load band R-3 itself was taken at (§5):

| | R-3 (filed) | Measured 2026-08-17 | Direction |
|---|---|---|---|
| `grep` forks, modal path | 12 | **14** | **up 17%** — more forks than filed |
| implied cost per `grep` fork | ~3.5 ms | **2.62 ms** | **down 25%** — cheaper than filed |
| aggregate (the number in the plan) | ~42 ms | **36.7 ms** | **down 13%** — the saving is smaller |
| `grep` forks *in `validate-bash.sh` itself* | 12 | **10** | 4 of the 14 are in a file R-3 never names |

The two errors partly cancel, which is why the headline scalar still looks approximately right.
It is not: the remedy R-3 describes buys **36.7 ms, not 42 ms**, and 4 of the forks it proposes to
remove are at `hooks/lib/is-true-flag.sh:41`, outside the file whose differential corpus is the
stated precondition for touching anything.

**Three findings R-3 does not contain, all larger than the error above:**

1. **`grep` is 51% of the modal path, not the whole story.** The hook execs **24 externals** on an
   ordinary safe command, of which 14 are `grep`. Framing the file as a grep problem hides the
   other 49%.
2. **The most expensive single fork in the file is `python3`, at 9.3× a `grep`.** One `python3`
   exec costs **24.45 ms** against `grep`'s 2.62 ms. Wherever `is-true-flag.sh`'s layer-2 tokenizer
   fires, that one fork outweighs nine greps. R-3 does not mention it.
3. **7.2 ms per call is a logger.** Lines 1008–1011 exec `jq` + `mkdir` + `date` on **every**
   invocation, unconditionally, to append one audit line — 10% of the modal path's cost, in the
   file's last four lines, and un-filed anywhere.

**Forks do explain the cost.** The fork model predicts 84–99% of measured wall clock across all 12
corpus classes (§4), so the "N forks × M ms" frame is the right one — it is simply pointed at the
wrong N and the wrong tool.

---

## 2. The `grep` binary — the premise holds, but not for the reason the warning implies

`MEMORY.md`'s `interactive-grep-is-ugrep` warns that `grep` on this box may resolve to ugrep. It
does — **but not for this hook, and the distinction is structural, not incidental.**

| Context | `grep` resolves to |
|---|---|
| the operator's interactive **zsh** (and therefore every Bash *tool call*) | a **shell function** from `shell-snapshots/snapshot-zsh-*.sh` (the ugrep rewrite) |
| `/bin/bash` — **the hook's own interpreter**, per its `#!/bin/bash` shebang | **`/usr/bin/grep`** |

A shell function is a property of the shell that defines it. Claude Code invokes
`~/.claude/hooks/validate-bash.sh` directly, the shebang selects `/bin/bash` (3.2.57), and no zsh
snapshot is ever sourced into it — so the rewrite is unreachable from the hook and every `grep` it
runs is BSD `/usr/bin/grep`. **R-3's premise is intact**, and the 2.62 ms marginal cost measured
here is BSD grep's.

The trap this *does* set is for the measurement, not the subject: a census run from an interactive
Bash tool call would time ugrep and attribute it to the hook. The harness resolves every external
with `command -v` under the same interpreter the hook uses and prints the resulting table into its
own report, so the substitution cannot happen silently.

---

## 3. Exec census — externals actually EXEC'd, by class

Two independent instruments, **agreeing exactly on all 12 classes**: (A) a PATH shim directory,
one absolute-path wrapper per external, logging one line per exec; (B) `bash -x` with `PS4`
carrying `${BASH_SOURCE}:${LINENO}`, filtered to lines whose first word is an external. (A) is the
count, (B) is the attribution; they share no mechanism, so agreement is corroboration.

| class | execs | breakdown |
|---|---|---|
| `safe-short` (`ls -la`) | **24** | grep×14 sed×3 jq×3 tr×1 mkdir×1 dirname×1 date×1 |
| `safe-median` | **24** | identical |
| `git-command` | **24** | identical |
| `bg-benign` (backgrounded, self-terminating) | **24** | identical |
| `safe-long` (~p95 length) | 25 | + python3×1 |
| `bg-park` (backgrounded poll loop → deny) | 26 | jq×4, + python3×1 |
| `rm-safe` | 27 | grep×15, **python3×2** |
| `pane-spawn` | **38** | jq×7 dirname×3 readlink×2 mkdir×2 date×2 find×1 cat×1 |
| `deny-early` (first hard-deny pattern) | **7** | jq×2 tr×1 sed×1 grep×1 dirname×1 cat×1 |
| `deny-ddl` | 15 | grep×5 sed×4 tr×2 jq×2 |
| `deny-flag` (real-flag deny) | 19 | grep×8 sed×4 tr×2 jq×2 python3×1 |
| `deny-rm` | 9 | jq×2 grep×2 python3×1 |

**The modal path is flat at 24.** Four different safe/git/background commands produce byte-identical
exec profiles, so for any command that is not denied, the cost is a constant and does not depend on
the command's content or length. That is the number worth carrying.

**An early deny is far cheaper than an allow** — 7 execs / 25.5 ms against 24 / 71.9 ms, 3.4× on
execs and 2.8× on wall clock. The ladder works as designed; the consequence is that the cost is
paid almost entirely by *safe* commands, which are ~all of them.

### Where the 14 greps are (instrument B)

| site | count |
|---|---|
| `hooks/lib/is-true-flag.sh:41` — layer-1 substring short-circuit, once per `check_real_flag` | **4** |
| `validate-bash.sh` lines 472, 503, 599, 624, 630, 657, 676, 684, 950, 956 | 10 |

`is-true-flag.sh:41`'s own comment estimates itself at "~1ms"; it measures **2.62 ms**. It is still
strongly net-positive — it exists to avoid the 24.45 ms `python3` behind it, a 9.3× trade — but the
comment understates both sides.

---

## 4. Wall clock, and whether forks explain it

Median of 40 timed runs per class, 3 warmup discarded, subprocess-timed from one long-lived
`python3` driver so no per-measurement interpreter startup lands inside the measured span.

| class | **unshimmed median** | p90 | shimmed median | shim tax |
|---|---|---|---|---|
| `safe-short` | **71.86 ms** | 83.17 | 124.19 | +52.34 |
| `safe-median` | **71.20 ms** | 76.09 | 123.20 | +52.00 |
| `bg-benign` | 71.09 ms | 75.33 | 115.73 | +44.64 |
| `git-command` | 74.28 ms | 91.89 | 116.46 | +42.19 |
| `safe-long` | 97.71 ms | 102.55 | 147.18 | +49.48 |
| `bg-park` | 102.29 ms | 105.68 | 158.39 | +56.10 |
| `rm-safe` | 130.94 ms | 141.81 | 179.18 | +48.24 |
| `pane-spawn` | 142.51 ms | 153.64 | 218.84 | +76.33 |
| `deny-early` | **25.46 ms** | 26.49 | 38.19 | +12.73 |
| `deny-ddl` | 40.14 ms | 42.04 | 66.43 | +26.30 |
| `deny-rm` | 56.89 ms | 58.27 | 74.39 | +17.51 |
| `deny-flag` | 74.89 ms | 78.39 | 107.73 | +32.84 |

🚨 **Quote the unshimmed column only.** The shim adds a whole extra process per exec — a +42 to
+76 ms tax, i.e. up to 73% inflation. The shimmed column is published solely so that nobody
re-derives a number from a shimmed run and believes it.

### Marginal cost of one exec, same load, same minute

`/bin/bash -c 'exit 0'` floor: **2.94 ms**. Marginal cost above that floor, per exec:

| python3 | jq | grep | dirname | tr | find | readlink | date | sed | cat | mkdir |
|---|---|---|---|---|---|---|---|---|---|---|
| **24.45** | 3.87 | **2.62** | 2.42 | 2.33 | 2.11 | 2.02 | 1.96 | 1.95 | 1.44 | 1.37 |

### The model

`predicted = bash_floor + Σ (exec_count × marginal_cost)`, using each class's own measured counts:

| class | execs | predicted | measured | residual | explained |
|---|---|---|---|---|---|
| `safe-short` | 24 | 65.16 | 71.86 | 6.70 | 90.7% |
| `safe-median` | 24 | 65.16 | 71.20 | 6.04 | 91.5% |
| `git-command` | 24 | 65.16 | 74.28 | 9.12 | 87.7% |
| `bg-benign` | 24 | 65.16 | 71.09 | 5.93 | 91.7% |
| `safe-long` | 25 | 89.61 | 97.71 | 8.10 | 91.7% |
| `bg-park` | 26 | 93.48 | 102.29 | 8.81 | 91.4% |
| `rm-safe` | 27 | 116.68 | 130.94 | 14.26 | 89.1% |
| `pane-spawn` | 38 | 123.18 | 142.51 | 19.33 | 86.4% |
| `deny-early` | 7 | 21.43 | 25.46 | 4.03 | 84.2% |
| `deny-flag` | 19 | 72.40 | 74.89 | 2.49 | 96.7% |
| `deny-ddl` | 15 | 40.09 | 40.14 | 0.05 | 99.9% |
| `deny-rm` | 9 | 48.51 | 56.89 | 8.38 | 85.3% |

**84–99% explained by exec count alone.** The residual is the subshell forks the exec count cannot
see: `printf '%s' "$CMD" | grep -q …` is *two* forked processes but *one* external exec, so every
count in §3 is a **lower bound on processes created** and the residual is where the difference
lives. It is small and it is one-directional, which is what a residual should be.

### Modal path decomposition (24 execs → 71.9 ms)

| grep×14 | jq×3 | sed×3 | bash floor | dirname×1 | tr×1 | date×1 | mkdir×1 | residual |
|---|---|---|---|---|---|---|---|---|
| 36.68 (51.0%) | 11.61 (16.2%) | 5.85 (8.1%) | 2.94 (4.1%) | 2.42 | 2.33 | 1.96 | 1.37 | 6.70 (9.3%) |

---

## 5. How far R-3 has decayed, and in which direction

**The load bands match, so the comparison is legitimate.** `HOOK_CHAIN_COST.md` §2 records its
figures at **load 14–18**; this census ran at **loadavg 15–18 on 10 CPUs** (`START 9.35`→`18.20`,
`END 15.20`, stamped in the report at both ends). This is the one condition under which two
millisecond figures from different months may be compared at all, and it happens to hold.

| | filed | measured | decay |
|---|---|---|---|
| grep forks | 12 | **14** | **+2 (+17%), upward** |
| ms attributed to them | ~42 | **36.7** | **−5.3 (−13%), downward** |

**Direction, stated plainly: the fork COUNT decayed upward and the ms figure decayed downward.**
Anyone quoting "12 forks" understates the work; anyone quoting "42 ms" overstates the prize. The
remedy R-3 gates behind a differential corpus is worth **13% less** than filed, and 4/14 of its
targets are in a file — `hooks/lib/is-true-flag.sh` — that R-3's precondition does not cover.

**Reproducibility, and it splits exactly along that seam.** Three independent runs of the harness
(smoke, full, post-refactor verify) produced **byte-identical exec counts for all 12 classes**,
while the wall clock moved with load — `safe-short` measured 71.86 ms at loadavg 15–18 and 69.55 ms
at 12.4–15.4 in the same ten minutes. The count is a property of the file; the millisecond is a
property of the afternoon.

⚠️ **The durable unit is the exec count, not the millisecond.** Fork cost is O(load) (§2 of the
plan, and `5c88633f`'s finding 3), so every ms here has a half-life measured in hours while the
count changes only when the file does. Re-derive rather than re-quote: `--runs 8` re-runs the
controls in under a minute and the model translates the same counts to the current load.

---

## 6. What this changes — levers, ranked by measured value

Each is a *measurement*, not a recommendation to edit; `validate-bash.sh` is a danger-pattern
safety gate and `denylist-enumerates-spellings-not-the-class` is a live scar on this exact file.

| # | lever | modal saving | note |
|---|---|---|---|
| 1 | The 14 greps → bash `=~` | **36.7 ms** (51%) | R-3's item, correctly sized. Still needs the differential corpus, and it must now cover `is-true-flag.sh:41` too. |
| 2 | The 3 `jq` execs → one payload parse | **~7.7 ms** | The hook parses the same stdin payload **3×** on the modal path (lines 46, 185, 1008) for `.command`, `.run_in_background`, `.session_id`. One `jq` yielding all three saves 2 of 3. Exactly the defect §2's audit named in `waiting-recycle.sh` (4 `jq -r` on one payload), unfixed here. |
| 3 | The tail logger's `mkdir`+`date` (lines 1010–1011) | **~3.3 ms** | Both are avoidable outright: `mkdir -p` runs on every call to create a directory that already exists, and `date` duplicates a timestamp the `jq` of lever 2 could emit. (The logger's third exec, the `jq` at 1008, is counted under lever 2, not here.) |
| 4 | `python3` layer-2 | 24.45 ms **when it fires** | Not on the modal path — the layer-1 grep short-circuit already prevents it. Named because it is the single most expensive fork in the file and R-3 omits it; the existing guard is the fix, and it works. |

Levers 2 and 3 total **~11 ms (15% of the modal path)**, carry none of lever 1's semantic risk —
no danger pattern changes — and are not filed anywhere.

---

## 7. Reproducing this

```
scripts/hook-fork-census.sh --runs 40            # full census, ~4 min
scripts/hook-fork-census.sh --quick              # harness smoke, ~40 s
```

Artifacts land in a `mktemp -d` (or `--out DIR`): `report.txt`, `execs.<class>.log` (argv per
exec), `attrib.<class>.txt` (file:line), `xtrace.<class>.txt`, `timing.json`, `controls.json`.

**The harness's own failure mode, and why it is guarded.** The first attempt at this measurement
used the same shim idea and destroyed itself: every shim body was `exec grep "$@"` while the shim
directory was still first on `PATH`, so the bare name re-resolved to the shim and exec'd itself
forever — **772,768 log lines, which is one infinite loop, not a measurement**. A count that large
does not read as broken; it reads as a finding. Five guards, all in `scripts/hook-fork-census.sh`:
shims exec **absolute** paths; those paths are resolved **before** the shim dir exists or touches
`PATH`; `build_shims()` refuses a target inside the shim dir; each shim carries an `_FC_DEPTH`
tripwire that aborts at 25 (exec replaces the process, so depth can only grow by nesting — the
self-exec signature); and `smoke_test()` proves one exec yields exactly one log line before any
measurement is trusted. A harness fault exits 1 and prints `FAULT`; it never emits a number.

**Corpus danger strings live only in `tests/fixtures/hook-fork-census-corpus.tsv`** and are fed to
the subject from that file. The live hook fires on every Bash tool call, so a danger literal typed
into a tool call gets the author's own call denied.

**Known limits.** (a) Exec counts are a lower bound on processes — pipelines of builtins fork
without exec'ing (§4). (b) `pane-spawn` execs depend on live lease/lineage state; its 38 is this
machine, this moment. (c) The corpus's length calibration comes from the last 4000 lines of
`bash-commands.log`, whose logger writes heredoc bodies as their own lines, so its tail is inflated
— the central percentiles (p25=18, p50=55, p75=100) are the trustworthy part, and the modal path is
flat at 24 execs across all of them anyway.
