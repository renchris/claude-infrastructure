# Shim premise, measured: does a Mach-O launcher stop the `#!` retention? (2026-10-22 00:20-00:40 CDT)

Box: MacBookPro18,2, macOS 15.8.1 (24H32) (`sw_vers`), boot 2026-10-21 14:06:30 CDT (`sysctl kern.boottime`).
Load during the run: 1-min load 93-213 on 10 cores (`load1` column of the rows file).

## Verdict

**MEASURED: the premise holds.** Running a script through the compiled launcher (`launch leaf.sh` ->
`execv("/bin/bash", {"bash", leaf.sh})`) retains **0.12 ± 0.11** elements per exec. That cannot be told
apart from `/bin/bash leaf.sh` (L − B = +0.10, 95% CI −0.14..+0.34), and it is 0.96 ± 0.12 below the
`#!`-by-path leaf. Converting a 2-deep `#!` chain (parent by path -> leaf by path) to bash parent ->
launcher -> leaf cuts the retention from **2.41 to 0.17** elements per invocation (C − D = 2.25 ± 0.11).
The launcher's residual cost relative to plain bash is **UNCLEAR** at this resolution (±0.12 per exec).
It is bounded above at about 0.34 per exec (95%), and the raw-zone fit puts it at −0.26, so it is
most likely 0.

## Table (residual = Δdata.kalloc.1024 − Δcred, elements retained per invocation)

Fit: least squares over 25 arms, Δresidual = drift·window_secs + Σ arm·n (the "drift-only" model, as
in `~/.cache/kalloc-158-ab/fit.py` model 2). Command:
`python3 -I ~/.cache/kalloc-longterm-ab/fit.py ~/.cache/kalloc-longterm-ab/rows-n3000.tsv win_secs`.

| Arm | What runs, per invocation | `#!` execs | Per invocation ±1 SE (residual) | const+drift model | raw Δkalloc (no cred subtraction) | per-arm drift-corrected median [min, max] (k=4) |
|---|---|---|---|---|---|---|
| S | `leaf.sh` by path | 1 | **+1.073 ± 0.093** | +1.004 ± 0.164 | +1.042 ± 0.127 | +1.080 [+1.016, +1.097] |
| B | `/bin/bash leaf.sh` | 0 | **+0.017 ± 0.095** | −0.044 ± 0.153 | −0.165 ± 0.129 | +0.050 [−0.140, +0.090] |
| L | `launch leaf.sh` (Mach-O -> /bin/bash) | 0 | **+0.116 ± 0.106** | +0.108 ± 0.110 | −0.256 ± 0.146 | +0.132 [−0.006, +0.178] |
| C | `parentC.sh` by path -> `leaf.sh` by path | 2 | **+2.413 ± 0.120** | +2.457 ± 0.149 | +1.909 ± 0.164 | +2.345 [+2.136, +2.791] |
| D | `/bin/bash parentD.sh` -> `launch leaf.sh` | 0 | **+0.166 ± 0.124** | +0.225 ± 0.171 | −0.089 ± 0.170 | +0.120 [+0.016, +0.370] |

Contrasts (residual, drift-only fit; the CIs come from the full covariance, a separate `python3 -I -c` over the same rows):

| Contrast | Value | Reading |
|---|---|---|
| S − B | +1.056 ± 0.113 | MEASURED: the `#!` exec costs about one element (same as the 15.8.1 result of 10-21, 1.098 ± 0.104) |
| S − L | +0.957 ± 0.115 | MEASURED: the launcher removes it (point estimate L/S = 0.11, so ~89% removed; raw-zone fit L/S = −0.25) |
| L − B | +0.098 ± 0.115, 95% CI [−0.14, +0.34] | UNCLEAR: no measurable launcher cost; raw-zone fit −0.091 [−0.42, +0.24] |
| D − B | +0.149 ± 0.122, 95% CI [−0.11, +0.40] | UNCLEAR: the 3-exec Mach-O chain shows no measurable cost; raw-zone fit +0.076 |
| C − D | +2.247 ± 0.113 | MEASURED: what converting one parent->leaf `#!` pair buys |
| C − 2S | +0.267 ± 0.179 | UNCLEAR: no evidence that a second `#!` in the same lineage costs more than the first; raw-zone fit −0.176 ± 0.245 |

Spread: the fit's residual SD is 480 elements per arm (about 0.16 per exec at n = 3000). The fitted fleet
drift was −3.8 ± 6.3 /s on the residual and +21.8 ± 8.6 /s on the raw zone. Idle arms (k = 5) read −629 to
+159 on the residual. The residual and raw-zone fits disagree on the sign of L and D, by about one SE.
That is noise around zero, and it is why L and D are reported as UNCLEAR rather than as zero.

## Against the public lineage claim (willmcginnis, claude-code#66020)

INFERRED from S and C: on 15.8.1 the first `#!` exec here is not cheap (S = 1.07, not 0.01-0.37), and a
nested second one adds about one more (C ≈ 2·S, C − 2S within noise). The 10-18 doc's nested A/B on 15.7.9
agrees (`docs/research/panic-2026-10-18-zone-map-shebang-leak.md:79-82`: 0.94, 1.98, 2.86 for 1, 2, 3 deep).
S's lineage was not clean: claude -> zsh -> `/bin/bash run.sh` -> leaf. I did not check whether any
ancestor was itself a `#!` exec, so "first in lineage" is not established for S. What the shim needs
holds either way: L and D contain no `#!` exec and retain about 0.

## Shim design facts this measurement exposes (MEASURED, read-only)

- Not every target is bash. Counting the 615 `#!` executables in `hooks/ bin/ scripts/` by first line:
  311 `#!/bin/bash`, 182 `#!/usr/bin/env bash`, 116 `#!/usr/bin/env python3`, 4 `#!/usr/bin/python3`,
  2 `#!/bin/sh` (`find … -perm -u+x` plus `head -1 | sort | uniq -c`). A launcher that always runs
  `/bin/bash` would break the 120 python scripts.
- `/bin/bash` and `env bash` are different shells: `/bin/bash` is 3.2.57, while `bash` on PATH is
  `/opt/homebrew/bin/bash` 5.3.15 (`--version`). Of the 182 `#!/usr/bin/env bash` files, 14 contain bash-4+
  syntax (`declare -A`, `mapfile`, `readarray`, `local -n`, `${x,,}`; grep heuristic). Examples:
  `bin/cc-do`, `scripts/ship-land.sh`, `scripts/land-lock.sh`, `hooks/lib/hook-deadline.sh`. Under a
  hard-coded `/bin/bash` they would fail (INFERRED). The launcher must take the interpreter from the
  script's own shebang (`/usr/bin/env bash` and `/usr/bin/env python3` are Mach-O relays, with no `#!` exec),
  the same rule as `scripts/hook-interp.py` (doc :248). Not measured: the `/usr/bin/env <interp> script`
  path. It contains no `#!` exec, so per this table it is expected to be about 0.
- Latency: L took 29.1 s per 3000 against 17.9 s for B and 17.9 s for S (mean `arm_secs`): about 3.7 ms
  more per call at load ~150, from the extra dyld exec. D took 40.7 s. On hot paths, a direct
  `/bin/bash script` call (B) is both leak-free and fastest. The launcher is for callers that run the
  script by name.
- The binary built with `/usr/bin/cc -O2` comes out ad-hoc signed by the linker
  (`codesign -dv launch` => `Identifier=launch`, arm64 Mach-O) and ran 24,000 times without a failure
  (`fails` = 0 in every row).

## Confounds and caveats

- **An EndpointSecurity client was active for the whole run.** The 10-min `sudo eslogger exec` census
  never stopped (see below), so every row has `es=1`. A public report ties vn_getpath failures to the ES
  exec path. Even so, S here (1.07 ± 0.09) matches the no-eslogger 15.8.1 figure of 10-21
  (1.098 ± 0.104, doc :334). INFERRED: the ES subscriber did not change the per-exec cost much. The L/B/D
  ≈ 0 result was not repeated without it.
- Load was not controlled, only recorded (93-213). Each arm ran 16-44 s. Arm order was counterbalanced
  over 4 cycles (S B L I C D / D C I L B S / L D S I B C / C B I D S L, then I), with idle arms set to
  the mean arm duration.
- Budget: 36,036 `#!` execs in total (`run.log`: 36 from an N=3 smoke test plus 36,000), under the 40,000
  cap. Estimated retained: 4·3000·1.07 + 4·3000·2.41 ≈ 41.8k elements ≈ 41 MiB in data.kalloc.1024 until
  the next reboot.

## Side finding: the exec census is wedged (needs the operator)

`bash /tmp/kalloc-exec-census.sh` (pid 84818) slept its 600 s, then ran `sudo -A pkill -INT -f
'^/usr/bin/eslogger exec$'` (`/tmp/kalloc-exec-census.sh:28`) behind an osascript password dialog. That
sudo exited without stopping eslogger. The script now blocks in `wait "$ES"` (:29), so `summary.txt`
will never be written. `/usr/bin/eslogger exec` (pid 90981, under `sudo` pid 90947) was still running at
00:40 CDT. `exec.jsonl` had reached 10.4 GB by 00:19 (`ls -la`), roughly 7 MB/s ≈ 25 GB/h; 3.8 TiB was
free (`df -h`). The census also now contains this test's execs: 36,036 `#!` execs of
`/Users/chrisren/.cache/kalloc-longterm-ab/{leaf.sh,parentC.sh}`, plus the `launch` and `bash` execs.
The summarizer should drop paths under `~/.cache/kalloc-longterm-ab/` and use the real window, not
`DUR=600`. I did not touch it: no kill or sudo under my rules.

## Files

- `~/.cache/kalloc-longterm-ab/launch.c`, `launch` (the launcher), `leaf.sh`, `parentC.sh`, `parentD.sh`
- `~/.cache/kalloc-longterm-ab/run.sh` (runner; run as `/bin/bash run.sh 3000`), `run.log`
- `~/.cache/kalloc-longterm-ab/rows-n3000.tsv` (25 rows, raw k/cred reads per arm), `rows-n3.tsv` (smoke test)
- `~/.cache/kalloc-longterm-ab/fit.py` (5-arm fit: const+drift and drift-only, per-arm medians)

## Critique

Adversarial review, 2026-10-22 00:45-01:00 CDT. I re-ran every check against the same files and the live
state. Each item is labelled MEASURED (the command is named) or INFERRED (the method is named). I wrote no
files other than this section and ran no `#!` leak arms.

### Verdicts, claim by claim

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | S +1.07, B +0.02, L +0.12 | CONFIRMED | `python3 -I fit.py rows-n3000.tsv win_secs` => S +1.073 ± 0.093, B +0.017 ± 0.095, L +0.116 ± 0.106. `arm_secs` as the time column moves each value by ≤ 0.003. |
| 2 | C +2.41, D +0.17, C − D +2.25 | CONFIRMED | same command => C +2.413 ± 0.120, D +0.166 ± 0.124, C−D +2.247 ± 0.113 |
| 3 | L − B UNCLEAR; "most likely 0" because the raw-zone fit gives −0.26 | VERDICT HOLDS, REASONING WEAK | The raw-zone fit uses the same 25 rows with a worse model (resid SD 658 vs 480), so its sign is not independent corroboration. A better model on the same rows: `dk = β·dc + drift·t + arms` with β free (`python3 -I -c` lstsq over rows-n3000.tsv). It gives β = 0.683 ± 0.133, resid SD 431, **L = −0.002 ± 0.107, L − B = +0.038 ± 0.106 (95% −0.18..+0.26)**, D − B = +0.126 ± 0.109, C − 2S = +0.127 ± 0.171. This is still UNCLEAR at about ±0.11. Read as a 95% bound, the launcher removes at least about 68% of the `#!` cost (1 − 0.34/1.07). The ~89% figure is only the point estimate. |
| 4 | "First `#!` in a lineage is cheap" does not show up here | REFUTED AS A TEST | Every Claude session here descends from a by-path `#!` exec of `bin/cc-close-attrib` (`#!/usr/bin/env bash`). Resume path: `scripts/limit-recover/lr-fire-resume.sh:1181` sets `LR_WRAP`, and `:1735`/`:1740` run `spawn … env … $wrap $bin`. Interactive path: `~/.zshrc:504,508` run `"$HOME/.claude/bin/cc-close-attrib" "$_bin"`. For this reviewer's session the ancestry is MEASURED (`ps -o pid,ppid,command` walk): zsh <- claude.exe <- `bash …/cc-close-attrib` <- expect <- `/bin/bash …/lr-fire-resume.sh`. For the researcher's session it is INFERRED (same launchers). So S measured a `#!` in a lineage that already held one, and C ≈ 2S is what both models predict. The run neither confirms nor refutes the public claim. The 10-18 nested A/B (doc :79-82) has the same problem (INFERRED: also run from a Claude session). Photon's own table gives depth 1 = 0.016 KiB (`kernel/web/photon.txt:229-240`), which supports the public claim. |
| 5 | Spread, load, budget, ~41.8k retained | CONFIRMED | load1 93.17-212.54 and fails = 0 in every row (rows file); run.log 36 + 36,000 `#!`; 4·3000·1.073 + 4·3000·2.413 = 41.8k (estimate, arithmetic) |
| 6 | eslogger on throughout; ES changed little | CONFIRMED, UNDER-ARGUED | es = 1 in every row, smoke test included. The study left out one point: B also matches its no-ES 10-21 value (+0.017 vs +0.007, doc :335). So the ES client added nothing measurable to a Mach-O exec either, which strengthens the L/B/D reading. |
| 7a | 615 `#!` executables: 311 / 182 / 116 / 4 / 2 | CONFIRMED | 312 / 182 / 116 / 4 / 2 at main HEAD 503da95d7 (00:32), via `find hooks bin scripts -type f -perm -u+x` + `head -1 \| sort \| uniq -c` |
| 7b | 14 `env bash` scripts use bash-4+ syntax and would probably break under `/bin/bash` | REFUTED | Every hit is a comment saying the script is **bash-3.2-safe**. That includes the four cited examples: `bin/cc-do:75`, `scripts/ship-land.sh:209`, `scripts/land-lock.sh:39`, `hooks/lib/hook-deadline.sh:43`. hook-deadline.sh is also mode 0644, a sourced lib rather than an executable. Over all `#!/usr/bin/env bash` files in hooks/ bin/ scripts/, `grep -nE 'declare -A\|mapfile\|readarray\|local -n\|declare -n\|${x,,}\|${x^^}\|wait -n\|[[ -v'` found **0** hits outside comments. A wider search (`${a[-1]}`, `\|&`, `&>>`, `coproc`, `${x@Q}`, `BASHPID`, `EPOCHREALTIME`, `declare -g`, `globstar`) found only false positives: git `--format='%(…)'`, embedded python, and `EPOCHREALTIME` used with a 3.2 fallback (`hooks/dod-persist.sh:42`, `scripts/handoff-fire.sh:4948`). The same first grep also hits 15 `#!/bin/bash` files; all are comments, strings or identifiers. The shebang-derived interpreter rule still stands, for the 120 python scripts and for fidelity: Homebrew bash 5.3 differs from 3.2 in behaviour, for example `EPOCHREALTIME` resolution. INFERRED (launchd's default PATH is `/usr/bin:/bin:/usr/sbin:/sbin`): `env bash` already resolves to 3.2 under launchd. The shim should therefore resolve `env` targets at run time from the caller's PATH, as `env` does, and not pin one bash. |
| 8 | L 29.1 s vs 17.9 s per 3000, +3.7 ms/call | NUMBERS SLIGHTLY OFF | Mean arm_secs (`python3 -I -c` over rows): L 28.63, B 18.04, S 17.87, so **L − B = 3.53 ms/call**. 29.1 is the first L arm alone (row 3: 29.158). L arms also ran at a higher mean load1 than B (159 vs 143), and every exec emitted an ES event. "From the extra dyld exec" is INFERRED. |
| 9 | Census wedged; it will never write summary.txt | STATE CONFIRMED; "NEVER" OVERSTATED | At 00:45:19, `ps` showed 84818 (bash census, etime 54:07), 90947 (`sudo -A …eslogger exec`) and 90981 (`/usr/bin/eslogger exec`) all alive. `exec.jsonl` was 23,029,338,417 B (`ls -la`): about 29 GB/h since 00:19, 25.6 GB/h since 23:51. 3.7 TiB free (`df -h`). summary.txt **is** written once eslogger exits for any reason: `wait` at :29 returns and the summarizer runs (:38-67). But it reports `per_hour = n·3600/600` (:59), which is wrong by the real-window ratio. INFERRED cause of the failed stop: sudo's credential cache (macOS default 5 min) expired during the 600 s sleep. The `sudo -A pkill` at :28 then needed a second password dialog, and `\|\| true` swallowed its failure. One `sudo` that both starts and stops eslogger avoids this. Three other sessions are already scanning exec.jsonl (`pgrep -lf kalloc-exec-census`: pids 125, 159, 84695). |
| 10 | The summarizer must drop `~/.cache/kalloc-longterm-ab/` paths | CONFIRMED | — |

### Missed: a cheaper, more robust instrument (MEASURED)

- run.sh reads cred and data.kalloc.1024 with **two separate `zprint` calls** (run.sh:18-19, :30-31). At this load each call takes 0.7-0.9 s (`time zprint`), so the reads are about 1-2 s apart. One snapshot (`zprint | awk '$1=="data.kalloc.1024"{k=$7} $1=="cred"{c=$7} END{print k-c}'`) collapses the jitter. SD of differences between consecutive reads:
  - single snapshot: **39** (n = 19, load1 99→76) and **9** (n = 15, load1 ~65)
  - two calls, in the same loop: **479** (n = 19) and 36 (n = 13, quiet)
- Within one snapshot, raw k (SD 711) and cred (SD 708) co-move almost exactly 1:1: k − c has SD 39, while k − 0.68·c has SD 231. So β = 1 is right when the reads are simultaneous. The β = 0.68 fitted above is an artefact of the time skew.
- INFERRED (variance comparison): the two-call jitter (479) matches the fit's per-arm residual SD (480), and the N = 3 smoke rows, with ~5 s windows, already had SD 365 (`rows-n3.tsv`). Most of the noise in this study comes from the instrument, not the fleet. With single-snapshot reads, the same design would resolve about ±0.01-0.03 per exec rather than ±0.1 (estimate: SE scaled by 40-120/480). Equivalently, it would reach ±0.1 with about 10x fewer `#!` execs.
- The open question costs no leak budget. L and B arms contain no `#!` exec, so a follow-up with single-snapshot reads and L/B (or L/B/D) arms only retains about 0. The real shim could be tested the same way: argv[0]/symlink dispatch, shebang parsing, PATH lookup for `env` targets. None of that was measured; `launch.c` hard-codes `/bin/bash` and takes the script in argv[1]. Stopping at UNCLEAR was a choice, not a budget limit.

### Missed: a possibly much cheaper lever (UNTESTED on 15.8.1)

- Suppose 15.8.1 behaves like willmcginnis's M1 26.6.2 and Photon's 26.5.x, where the first `#!` in a clean lineage costs 0.01-0.37 and 0.016 respectively (`kernel/issue66020-comments.md:1015,1022`; `photon.txt:229-245`, where Photon says the buffer is not released "when the calling program was itself launched from a script"). Then the by-path `cc-close-attrib` root (the 3 call sites in #4) taints every session. Each hook's or tool chain's first by-path `#!` would then pay a full element. Starting that wrapper with an explicit interpreter would make the first `#!` of every chain nearly free. That is a change of about 3 lines, against shimming ~600 entries. The shim remains the catch-all for nested script→script calls either way.
- Decisive test (operator action, not run: it needs a runner spawned by launchd or a fresh kitty window, which these rules forbid). From a clean-lineage `/bin/bash run.sh` with single-snapshot reads, run S and B arms, 4 × 1000 each: at most 4,000 `#!` execs, at most ~4 MiB. If S ≈ 0, fix the roots first. If S ≈ 1, the M4 26.4.1 "every `#!` costs" behaviour applies (comments :1014), and only the shim helps.
- A zero-cost alternative uses the census. Each event in `exec.jsonl` carries `ppid`, `original_ppid` and `parent_audit_token` (MEASURED: key list of the first `script` event, via `head -c 400000 \| grep -m1 '"script":{'`). Split the window's `#!` execs by whether any in-window ancestor was itself a `#!` exec. Then compare each class's count with the zone residual rate (single-snapshot reads) over the same window.

### Inferred, but stated as measured

- Summary 4 ("does not show up here"): inferred, and the design cannot show it (see #4).
- Summary 7 ("14 env bash scripts use bash-4+ syntax"): a grep heuristic, and false (see #7b).
- Summary 3 ("most likely zero"): rests on swapping models on the same data. The free-β fit is better support and still gives UNCLEAR.
- Summary 8 ("+3.7 ms, from the extra dyld exec"): the measured figure is 3.5 ms, and the attribution is inferred.
- Correctly labelled already: L ≈ B is MEASURED only for the argv[1] launcher that execs `/bin/bash`. The `env`-relay and shebang-parsing paths are INFERRED ≈ 0.
- One INFERRED observation from the snapshot data: the 1:1 instantaneous k/cred co-movement suggests one 1 KiB data allocation per credential. That fits the AppleSystemPolicy `credLabelUpdateExecve` site that willmcginnis traced (comments :1096), but nothing here tests it.

## T-1 (2026-10-22)

The trampoline's own cost (REPORT §3 Phase 0, Q2). Run 2026-10-22 01:38:10-01:45:49 CDT, macOS 15.8.1, same
boot as above (2026-10-21 14:06:30), 1-min load 30-77 on 10 cores, no EndpointSecurity client (`pgrep -x eslogger`
empty, unlike the run above).

**Verdict: PASS. L − B = +0.020 ± 0.017 elements per exec (95% CI −0.012..+0.053), below the 0.1 bar.**
The trampoline adds no measurable kernel retention over `/bin/bash leaf.sh`; Q2 moves from 80% to settled
at this resolution. The design resolves ±0.017 per exec, about 7x finer than the ±0.11 above, from
single-snapshot reads, as the Critique predicted.

- **Arms** (N = 3000 each, 12 interleaved pairs, order alternated L B / B L; 5 idle arms for drift):
  - L: `tramp leaf.sh`. `tramp` is a shebang-PARSING Mach-O (reads line 1, execs its interpreter and
    optional argument with the script as argv), built `/usr/bin/cc -O2`, ad-hoc signed by the linker. This
    is the real trampoline's parse path, unlike `launch` above, which hard-coded `/bin/bash`.
  - B: `/bin/bash leaf.sh`. Neither arm runs a `#!` exec, so the run spent no leak budget.
- **Instrument:** one `zprint` per reading, `k − cred` from the same table
  (`zprint | awk '$1=="data.kalloc.1024"{k=$7} $1=="cred"{c=$7} END{print k, c}'`).
- **Fit** (drift-only, as above): Δresidual = drift·window + L·n_L + B·n_B over 29 rows; residual SD 111
  elements per arm (480 above). L = +0.038 ± 0.022, B = +0.018 ± 0.017, drift +8.9 ± 3.2 /s.
- **Paired check** (each pair drift-corrected, L − B): mean +0.020, SD 0.041, SE 0.012, median +0.017, n = 12;
  10 of 12 within ±0.045, the largest +0.116 (pair 12, load1 58-71). Without the drift term the paired mean
  is +0.040 ± 0.011, still under the bar.
- **Latency:** L 17.75 s against B 11.25 s per 3000 (mean `arm_secs`), so **+2.2 ms per call** at load 30-77,
  against +3.5 ms at load ~150 above. Hot paths should still call `/bin/bash script` directly; the
  trampoline is for callers that run a script by name.
- 0 failures in 72,000 execs.

Files: harness `t1-tramp.c.txt` and `t1-run.sh.txt` beside this file (copies of `~/.cache/kalloc-t1/tramp.c`
and `run.sh`, run as `/bin/bash run.sh 3000 12`); rows `~/.cache/kalloc-t1/rows-n3000.tsv`. T-0 (the
clean-lineage test) was not run: it needs the operator to open a kitty window started by launchd.
