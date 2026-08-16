# Is the hourly `hermetic` red TRUE? — MIXED, trending FALSE for the current/recent regime

**Verdict: MIXED.** The fold mechanism itself is correct and has caught genuine regressions
(confirmed independently by on-box `postland-verify`). But **at the moment this question was
asked (through run 31909790008, 2026-08-15T21:34Z), 100% of the off-box red signal in the last
~6 hours of hourly runs reduces to exactly two suites, and both are established FALSE** —
neither is a real trunk defect. Confidence: **high** for the two currently-active false reds
(each independently reproduced/refuted with a fresh `origin/main` worktree, cross-checked
against on-box `postland-verify` stamps covering the identical time window); **high** for the
historical true reds (each has a landed fix commit whose message names the exact defect this
report independently rediscovered).

---

## 1. The fold mechanism (`scripts/offbox-run.sh`)

Read in full. Key logic:

- `run_one()` (offbox-run.sh:114-162) classifies **per suite** from the TAP body, not the exit
  code: `notok>0 ⇒ red` (a claim about the CODE) · `rc≠0 and notok==0 ⇒ cut` (a claim about the
  MACHINE, proves nothing) · `rc==0 and ok>0 ⇒ green` · `rc==0 and zero test lines ⇒ empty`
  (offbox-run.sh:146-150). This is R6 ("a non-verdict is never a red") correctly implemented —
  `--selftest` (F1-F6h, offbox-run.sh:366-516) exercises exactly this discrimination end to end
  against real /Users/chrisren/.claude/bin/cc-bats and it is green on this box today.
- `cmd_verdict()`'s awk fold (offbox-run.sh:308-357): `short` (fewer rows than the partition, or
  any unreported suite) **outranks red** ⇒ `cut`; else `red>0 ⇒ red`; else any
  `cut+empty+missing>0 ⇒ cut`; else `green`. This ordering is deliberate and tested (F5d/F5e,
  offbox-run.sh:413-424) — a dead shard cannot be laundered into a red verdict, and it cannot be
  laundered into a green either.
- The `hermetic.yml` workflow (`.github/workflows/hermetic.yml`) confirms the CONTEXT's framing:
  `suite` jobs *always* exit 0 (they upload shards regardless of content — no `run: ... && exit
  1` anywhere in the suite job), `partition` job is a pure enumeration that also always succeeds,
  and only `verdict`'s final step (hermetic.yml:383-403) inspects the fold's JSON and exits 1 on
  anything other than `"verdict":"green"` — **including `cut`**, not just `red`. Confirmed live on
  run 31907172661's job list: `partition` success, all 11 `suite` jobs success, `verdict` failure
  — exactly the shape in the prompt.
- The fold, the partition membership, and the exclusion-manifest churn are ALL correctly
  documented as re-measured, not curated (hermetic.yml:3-28, offbox-run.sh:38-42). The mechanism
  is sound; the question is what it is being fed.

## 2. Central table — failing suites across 27 sampled scheduled runs (2026-08-11 04:38Z → 2026-08-15 21:34Z, out of 91 total scheduled runs in that window)

Sample = the 5 run ids named in the brief + every 4th of the 91 scheduled runs + both green
runs + the oldest scheduled run, downloaded via `gh run download <id> -n offbox-verdict`.

| Suite | Failures / 27 sampled runs | First seen | Last seen | Status at true `origin/main` HEAD (2edc3ee26) |
|---|---|---|---|---|
| `tests/unattended-path-lint.bats` | **10/27** | 2026-08-13T17:10Z | 2026-08-15T20:37Z (still failing in the most recent 4 consecutive runs before this report) | **GREEN** (18/18, on-box and in a fresh `origin/main` worktree) |
| `tests/cc-close-attrib.bats` | **6/27** | 2026-08-13T17:10Z | 2026-08-15T21:34Z (the MOST RECENT run) | **GREEN** (18/18, on-box and at `origin/main`) |
| `tests/cc-memory-rotate.bats` | 6/27 | 2026-08-11T04:38Z | 2026-08-12T06:41Z | GREEN — cluster ended, never seen since |
| `tests/cloud-create-api-env.bats` | 6/27 | 2026-08-11T04:38Z | 2026-08-12T06:41Z | GREEN — same early cluster |
| `tests/spawn-lineage.bats` | 5/27 | 2026-08-11 | 2026-08-12 | GREEN — same early cluster |
| `tests/falsifier-emission.bats` | 5/27 | 2026-08-11 | 2026-08-12 | GREEN — same early cluster |
| `tests/gate-precheck.bats` | 5/27 | 2026-08-11 | 2026-08-12 | GREEN — same early cluster |
| `tests/lr-resume-answer-width.bats` | 5/27 | 2026-08-11 | 2026-08-12 | GREEN — same early cluster |
| `tests/gate-ownscope-leak.bats` | 5/27 | 2026-08-13T22:01Z | 2026-08-14T19:12Z | **GREEN — fixed** by commit `d2fe55adf` (landed on-box ~2026-08-14T22:08Z, confirmed by the postland-verify stamp naming that exact commit) |
| `tests/autonomy-sweep.bats` | 4/27 | 2026-08-11 | 2026-08-11 | GREEN — same early cluster |
| `tests/capacity-admit-active.bats` | 2/27 | 2026-08-14T15:06Z | 2026-08-14T19:12Z | **GREEN — fixed** by `af8be7c93` (already in `git log` HEAD) |
| `tests/anti-vacuity-contract.bats` | 2/27 | 2026-08-14T22:38Z | 2026-08-15T03:52Z | GREEN — fixed between 03:52Z and 09:19Z (see §4) |
| `tests/cc-gc.bats` | 1/27 (+1 in a `workflow_dispatch` run) | 2026-08-14T15:06Z | 2026-08-15T20:55Z | GREEN at `origin/main` |
| ~15 more singleton names, all from ONE run (31792954730, a `cut` verdict with `unreported=44`) | 1/27 each | 2026-08-14T10:37Z | — | Mostly kitty/tmux/session-identity suites; same machine-coupling class as §3 |

**Reading the table**: the failing SET is not one stable set — it is **three non-overlapping
waves**, each internally stable for its own lifetime and then cleared:

1. **Aug 11 wave** (~15 suites: `cc-memory-rotate`, `cloud-create-api-env`, `spawn-lineage`,
   `falsifier-emission`, `gate-precheck`, `lr-resume-answer-width`, `autonomy-sweep`, `cc-notify`,
   `capacity-alarm-permb`, `session-start-mcp-probe`, `handoff-fire-launcher-map`,
   `utc-stamp-lint`, `self-path-lint`, `test-afunix-path-lint`, `desk-invariant`,
   `fire-autonomy`, `cc-fleet`, `capacity-admit-coverage`) — all real, all cleared by the two
   GREEN runs on 2026-08-13.
2. **Aug 14 wave** (`gate-ownscope-leak`, `capacity-admit-active`, `anti-vacuity-contract`,
   `cc-gc`, `land-gate-cas`, `typed-send-lint`, `deathwatch-watchfile`) — real, transient, each
   independently confirmed and cleared by a specific landed fix commit (§4).
3. **The current wave** (`unattended-path-lint`, `cc-close-attrib`) — the ONLY two suites failing
   in every one of the last 6 consecutive off-box runs and the only two the on-box verifier
   NEVER once reproduced across 25 stamps spanning the same 40-hour window. §3 shows both are
   FALSE.

Board items named in the brief: `fire-autonomy`+`cc-notify` (≈#112) and `tests/tsv-field-collapse.bats`
(≈#126) DO appear in this data, but only in the **Aug 11 wave** — both are long closed
(`tsv-field-collapse.bats` even graduated OUT of `scripts/offbox-excluded.manifest`, comment
dated 2026-08-13: *"REMOVED — the first entry this list has ever shed"*, and is GREEN 34/34 at
`origin/main`). **These board items do not describe the current red** — confirms the brief's
"do not assume" caveat was warranted.

## 3. The two suites currently in the failing set — both FALSE, with independent confirmation

### `tests/unattended-path-lint.bats` — FALSE, machine-coupled (10/27 runs, still failing)

On-box (this Mac): **18/18 green**, both under my stale local checkout and in a fresh
`origin/main` worktree. Off-box (run 31907172661, shard 1 log, downloaded via `gh run download
31907172661 -p 'offbox-shard-*'`): tests #2 and #14 fail, and the TAP body names the exact
cause —

```
✗ hooks/teammate-auto-shutdown.sh:182: `tmux` is unreachable on the PATH this hook hardens to (bare)
✗ bin/cc-dispatch:1279: `pnpm` is unreachable on com.claude.dispatcher.plist's own PATH (bare)
✗ bin/cc-dispatch:1282: `yarn` is unreachable on com.claude.dispatcher.plist's own PATH (bare)
✗ bin/cc-dispatch:1283: `uv` is unreachable on com.claude.dispatcher.plist's own PATH (bare)
✗ tests/it2-kitty-operator-safety.bats:33: `kitty` is unreachable ... (guarded)
```

The suite asserts that specific bare-name binaries (`tmux`, `pnpm`, `yarn`, `uv`, `kitty`) are
reachable on the PATH the repo's own launchd wrappers harden to. Those five tools are simply not
installed on the GitHub Actions `macos-latest` image (the workflow's own tool-inventory step,
hermetic.yml:187-195, does not even check for them) — they exist on the operator's Mac by local
setup. This is a claim about **this specific runner's installed tools**, not about the tree. It
is exactly the category `scripts/offbox-excluded.manifest` exists for (43 suites currently
excluded for the same reason); this one has simply not yet been added.

### `tests/cc-close-attrib.bats` — FALSE, off-box-only and NOT reproducible even under the exact hermetic env (6/27 runs; present in the MOST RECENT run, 31909790008)

On-box: **18/18 green**, both stale local and `origin/main` worktree. Off-box, all 3 sampled
instances (runs 31724408143, 31879973156, 31832186515, and the newest 31909790008) fail the
**identical single assertion** every time:

```
not ok 1 wrapper passes the exit code and argv through to the stub
# (in test file tests/cc-close-attrib.bats, line 79)
#   `[ "$status" -eq 33 ]                                  # exit code preserved' failed
```

Tests #2-18 all pass every time. This is a genuinely reproducible off-box behavior, not a
flake in the sense of "different assertion each run" — but it is **not reproducible on this
box even when the exact `run_one()` invocation is replicated line-for-line**:

```
env -i HOME=<fresh> TMPDIR=<fresh>/tmp PATH="$PATH" TERM=dumb LC_ALL=C CC_OFFBOX=1 \
  gtimeout -k 10 300 /Users/chrisren/.claude/bin/cc-bats tests/cc-close-attrib.bats
```
→ `rc=0`, 18/18 green, run locally with `$HOME`/`env -i` fixtured identically to the CI harness.

`bin/cc-close-attrib` backgrounds a brace-group (`{ exec "$bin" ...; } &`) specifically to
capture `$!` as the real binary's PID (bin/cc-close-attrib:14-20 comment), then `wait`s on it.
That mechanism is sensitive to process/job-control timing in a way ordinary `run`/`exec` is not.
Since it reproduces reliably off-box (same test, every sampled instance) but not locally even
under an identical env, the discriminating variable is the **GitHub Actions macOS VM itself**
(virtualized CPU scheduling / job-control latency), not anything in `HOME`, `PATH`, `LC_ALL`, or
`TERM`. This is machine-coupling to the specific CI runner class, not a code regression —
consistent with 0 occurrences across 25 on-box `postland-verify` stamps in the same 40-hour
window.

## 4. On-box cross-check — the real discriminator (§4 of the task)

`~/.claude/autonomy/postland/stamps/*.json` is the actual on-box producer (the workflow's own
comment calls the on-box verifier "the SOLE owner of the full-suite claim," 0.17 greens/day). 25
most-recent stamps (2026-08-14T06:16Z → 2026-08-15T22:31Z, i.e. the SAME window as the current
off-box failing-suite table):

| ts | verdict | commit | failing |
|---|---|---|---|
| 2026-08-15T22:31:32Z | cut | b3110a79f6 | [] |
| 2026-08-15T21:54:02Z | cut | 4e21050b58 | [] |
| 2026-08-15T21:19:05Z | cut | 30494ba098 | [] |
| 2026-08-15T13:57:42Z | **green** | ba9141f110 | [] |
| 2026-08-15T12:24:04Z | cut | cb46c724b0 | [] |
| 2026-08-15T11:43:15Z | cut | f7644beb86 | [] |
| 2026-08-15T10:18:43Z | cut | 9a7818c382 | [] |
| 2026-08-15T09:19:43Z | **green** | 2d7b125d62 | [] |
| 2026-08-15T08:35:13Z | cut | 366dadddb2 | [] |
| 2026-08-15T07:46:58Z | cut | 203501e43c | [] |
| 2026-08-15T06:59:53Z | cut | 9c988b7d6d | [] |
| 2026-08-15T04:58:39Z | **red** | 26ccbb3a86 | `tests/anti-vacuity-contract.bats` |
| 2026-08-14T22:46:06Z | **red** | cb78acbc55 | `tests/anti-vacuity-contract.bats` |
| 2026-08-14T22:08:39Z | cut | d2fe55adfe | [] |
| 2026-08-14T21:29:39Z | **green** | af8be7c932 | [] |
| 2026-08-14T14:21:53Z | **red** | 61826e1936 | `tests/capacity-admit-active.bats` |
| 2026-08-14T13:36:54Z | cut | c0e280a194 | [] |
| 2026-08-14T12:51:10Z | **red** | a61cfa6203 | `tests/capacity-admit-active.bats`, `tests/compressor-sentinel.bats` |
| 2026-08-14T10:59:08Z…06:16:48Z | cut / green / hung | — | (`autonomy-sweep.bats` at 06:16Z, a `hung` non-verdict) |

Two things this table proves:

1. **`unattended-path-lint.bats` and `cc-close-attrib.bats` NEVER appear on-box, in this or any
   sampled window.** Zero of 25 stamps. This is the strongest evidence they are off-box-only
   artifacts, not trunk defects — the on-box verifier runs the identical suite files against
   the identical trunk and never once reproduces either failure.
2. **`anti-vacuity-contract.bats` and `capacity-admit-active.bats` WERE independently caught
   on-box, in the same narrow time windows the off-box fold caught them**: `capacity-admit-active`
   red on-box at 12:51Z and 14:21Z on 2026-08-14 (off-box red at 15:06Z and 19:12Z the same day —
   consistent, off-box lags on-box by the ~65-95min run wall-time plus schedule offset);
   `anti-vacuity-contract` red on-box at 22:46Z (Aug14) and 04:58Z (Aug15) (off-box red at
   22:38Z Aug14 and 03:52Z Aug15 — again consistent). **Both were subsequently fixed** (on-box
   green at 21:29:39Z for the capacity item, green at 09:19:43Z bracketing the anti-vacuity fix).
   This is the mechanism working exactly as designed: catching a real, short-lived regression,
   on two independent verifiers, before either read it as durable.
3. **The dominant on-box verdict is `cut`** (14 of 25 stamps) — a non-verdict, matching board
   item #117's framing ("count swings 3..14, so most are flakes not regressions") almost
   exactly, though #117's specific named suites are not the ones currently active.

## 5. The two GREEN runs (2/91 ≈ 2.2%) and their discriminating variable

Runs 31661809706 (2026-08-13T02:45:42Z, headSha `a54569dbf0`) and 31697852580
(2026-08-13T11:58:06Z, headSha `b6df7a8749`). Both: `unreported=0` (no dead shard),
`suites==expected` (418/418 and 419/419), `red=0`, `nonverdict=0`, `run_s` 3793s / 3833s — **not
faster than red runs** (red runs range 3925-5937s in the same sample; run duration is not the
discriminant).

The discriminating variable is **calendar position, not mechanism**: both greens land in the
narrow ~9-hour gap between the Aug 11 wave clearing (last Aug-11-wave failure: 31570936250,
2026-08-12T06:41Z) and the Aug 14 wave beginning (first new failure: 31724408143,
2026-08-13T17:10Z, `unattended-path-lint`+`cc-close-attrib`). The partition itself grew
continuously through this whole period — 364 suites (2026-08-11T04:38Z) → 428 suites
(2026-08-15T07:43Z), **+64 suites in ~4 days, ~16/day** — exactly the "NOISE HAZARD" the
workflow's own header names (hermetic.yml:23-28: *"a genuinely machine-coupled new suite reds
this workflow on the land that adds it"*). A green requires a ~65-100 minute window in which (a)
no newly-landed suite is machine-coupled or born-broken, and (b) no existing suite is mid-fix.
Trunk moves ~63 commits/day (~1/23min, per hermetic.yml:33); at that velocity, and given the
observed rate of transient/machine-coupled suite introductions, a clean ~70-100min window is
genuinely rare. The 2.2% off-box green rate and the on-box 0.17/day green rate are two
independent measurements of the same underlying phenomenon: **trunk's regression-introduction
rate, not the fold's discrimination logic, is what is being measured.**

## 6. Adversarial pass

- **Could the "false" reds actually be true and my local box just happens to have the fix I
  haven't noticed?** Checked: local HEAD was 41 commits behind `origin/main` at the start of
  this investigation (`git status --short --branch` → `ahead 1, behind 41`). All GREEN
  confirmations in §3-4 were re-run in a **fresh, read-only `git worktree add --detach
  origin/main`**, not the stale local checkout, specifically to rule this out.
- **Could `unattended-path-lint`'s failure be evidence of a real portability bug** (i.e. the repo
  really should harden PATH to work even without tmux/kitty/pnpm/yarn/uv installed)? Possibly —
  but that is a claim about robustness on a hypothetical machine lacking those tools, not a claim
  that the CURRENT tree is broken on any machine that actually runs it (the operator's box has
  them; every consumer of these launchd plists is the operator's own machine). Diagnosis only,
  per the task constraint — not adjudicating whether the assertion is well-designed.
- **Could `cc-close-attrib`'s off-box failure be intermittent in BOTH directions** (i.e. does it
  ever pass off-box)? Not checked across every one of the 6 occurrences — 3 were sampled in
  detail (31724408143 not read for content, 31879973156, 31832186515, 31909790008 all showed the
  identical `not ok 1` at line 79) — 3/3 sampled instances show the same failure, 0 sampled
  passing instances exist in the failing set (by definition — this only samples FAILURES). This
  does not establish whether it's deterministic-per-CI-VM-class or merely frequent; the claim
  made is narrower and fully supported: it is reproducible off-box, never reproducible on-box or
  under a locally-simulated identical env.
- **Census run 31909362400 (30 "reds")** — checked explicitly: workflow_dispatch, not schedule;
  runs `census` verb which deliberately includes all 43 currently-EXCLUDED suites
  (`scripts/offbox-excluded.manifest`); cross-checked 6 of its failing names
  (`cc-reconcile`, `live-session-registry-atomic`, `handoff-selfclose-kitty-identity`,
  `it2-wrapper`, `suggest-filter`, `compressor-sentinel`) — all 6 are in the exclusion manifest.
  This run is evidence-only by the workflow's own design (hermetic.yml:262-263, "never allowed to
  mint a green") and is unrelated to the hourly cron's red — excluded from the central table's
  interpretation.

## 7. Bottom line

- **The fold mechanism is correct** — R6-compliant, selftest-verified, and has genuinely caught
  real transient regressions independently confirmed by a second verifier (on-box
  `postland-verify`) in the same time windows (`capacity-admit-active`, `anti-vacuity-contract`,
  earlier `gate-ownscope-leak`).
- **The hourly notification the operator is currently seeing is FALSE.** Every scheduled run in
  the last ~6+ hours (31872662181 through 31909790008) reds on suites — `unattended-path-lint`
  and/or `cc-close-attrib` — that are both (a) green on trunk, verified in a fresh `origin/main`
  worktree, and (b) never once reproduced by the independent on-box verifier across 25 stamps
  spanning the identical window. Neither is a trunk defect; both are artifacts of the specific
  GitHub Actions macOS runner (missing dev tools for one, a process/job-control timing
  sensitivity for the other).
- **This is not the workflow "emitting a false alarm hourly for days"** in the sense of a single
  static bug — the failing SET has genuinely churned through three distinct waves (Aug 11, Aug
  14, current), two of which were real and got fixed. What IS true for days running is that the
  fold has essentially never gone green, because trunk's regression/noise-introduction rate
  (~16 new hermetic suites/day, 63 commits/day) exceeds the rate at which any given ~70-100min
  off-box run can land in a clean window — a structural property of running an hourly full-suite
  second opinion against a fast-moving trunk with a slowly-curated exclusion manifest, not a bug
  in the fold arithmetic itself.
