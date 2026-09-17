# T3 — What fires `scripts/deploy-live.sh` after a land, and why converging is effectively manual

Repo READ-ONLY; nothing mutated. Legend: **RAN** = executed this session · **READ** = read in a file.
Conviction per section stated at the end of each.

---

## Headline (answer first)

**Nothing fires `deploy-live.sh` after a land.** `scripts/ship-land.sh` contains four textual
occurrences of `deploy-live.sh` (`:2437`, `:2480`, `:4173`, `:4205`) and **all four are comments** —
RAN `grep -nE "deploy-live\.sh" scripts/ship-land.sh` → those four lines only. The post-land tail
(`post_release_finish`, `scripts/ship-land.sh:1467`) discharges the rollback ref and runs the
stranded sweep; it never converges.

The only *automated* caller on the box is a **clock**, not a land-trigger: the launchd job
`com.claude.deploy-live`, `StartInterval 600`. It is genuinely alive (RAN `launchctl print` →
`runs = 39`, `last exit code = 0`, `state = not running`, i.e. ticking and exiting clean).

So the gap is not a dead scheduler. It is that **the timer refuses to advance until a lag budget
trips (25 commits / 6 h), and a land signals nothing** — so a landed commit sits inert for a
**median 2.3 h** (p90 16 h, max 41 h; §4) unless a human or an agent runs the converger by hand.
Measured, **40.1 % of all live-layer advances in the last 36 days were run by hand**, not by the
timer (§1.3).

---

## §1 — Caller inventory: scheduled vs. advisory

### 1.1 The one scheduled caller

| | |
|---|---|
| Declaration | `~/Library/LaunchAgents/com.claude.deploy-live.plist` |
| Command | `exec "$D" --auto`, `$D` = `~/.claude/scripts/deploy-live.sh` with a repo-path fallback |
| Declared cadence | `StartInterval 600` (= 144/day **declared**) |
| **Loaded?** | YES — RAN `launchctl list` → `-  0  com.claude.deploy-live` |
| **Delivered runs (short window)** | RAN `launchctl print gui/501/com.claude.deploy-live` → `runs = 39`. Boot = 2026-09-16 16:28:30 (RAN `sysctl -n kern.boottime`), sample at 2026-09-17 00:02 → **7.56 h ⇒ 5.16 runs/h = 124/day-equivalent, 86 % of declared** |
| **Delivered runs (long window)** | `migrations_converge` is UNCONDITIONAL and early (`scripts/deploy-live.sh:1895`, before target selection at `:2017`), and emits one `deploy-migrations: migrate:` line per run. RAN `grep -c "^deploy-migrations: migrate:"` on `deploy.log` → **3 820** lines; first such line at log line 727 and `scripts/deploy-migrations.sh` was added 2026-08-07 (RAN `git log --diff-filter=A`), so over ~40.5 days ⇒ **≈94 runs/day = 65 % of declared**. The gap is machine downtime (two kernel panics on 2026-09-16). |

**Verdict: the timer is real and delivering at 65–86 % of its declared rate.** "Cadence in a config
file" is not what is broken here.

### 1.2 Everything else that names deploy-live is a MESSAGE, not a trigger

RAN: `grep -rnE '(bash|exec|\$\()[^#]*deploy-live\.sh' scripts/ hooks/ bin/ commands/`.

| Site | What it is |
|---|---|
| `scripts/deploy-now.sh:56,73` | The **operator** entrypoint (`bash ~/.claude/DEPLOY-NOW.sh`), a thin front-end that execs deploy-live. **Nothing schedules it** — RAN grep across all `*.plist`/`*.sh`: the only non-doc references are `install.sh:811,819` creating its symlink. Manual by design. |
| `hooks/session-continue.sh:1097` | A **Stop-hook block message** to the model: `🚀 SHIP FLOOR — … Converge it now: bash $(git rev-parse --show-toplevel)/scripts/deploy-live.sh`. It *prints an instruction*; it does not execute. Fires on going **idle** with a breached budget, **not on land**. |
| `hooks/operator-readout.sh:858` | `dact=" → bash scripts/deploy-live.sh"` — a rendered string for the operator block. |
| `scripts/wrap-ledger.sh:1869`, `:2197` | The `🚀` rung's readout text. Print only. |
| `hooks/completion-assert.sh:701,703` | Close-gate *facts* text naming the converge command. Print only. |
| `hooks/activation-watch.sh:470,491`, `hooks/lib/why-tier.sh:249`, `scripts/limit-recover/lr-handoff.sh:507`, `scripts/deploy-link-parity.sh:509`, `scripts/deploy-parity-assert.sh:1447`, `scripts/handoff-fire.sh:8370`, `migrations/00{09,11,16,20,21,22,24,26,28}-*.sh` | All advisory strings telling a reader to run it. |
| `hooks/validate-bash.sh:1352` | A **deny** on a bare `git merge/pull --ff-only` in the shared checkout, whose message names deploy-live as the sanctioned alternative. A guard, not a caller. |
| `scripts/autonomy-sweep.sh` | **ZERO** references — RAN `grep -c 'deploy-live' scripts/autonomy-sweep.sh` → `0`. The sweep does not converge. |
| `.git/hooks/` | RAN `ls -la .git/hooks/` → only `commit-msg`, `pre-commit`, `pre-merge-commit`, `pre-push`. **No `post-merge`/`post-checkout`/`post-receive`.** |
| cron | RAN `crontab -l` → **exactly one entry**, `15 9 * * * /Users/chrisren/Development/personal/bin/mb-hpc-price-watch`, unrelated. **No cron entry for deploy-live.** |

### 1.3 Who actually performs the advances — measured, not assumed

`deploy.log` is the launchd job's `StandardOutPath` and deploy-live has **no log wiring of its own**
(`say()` at `scripts/deploy-live.sh:393` prints to stdout; `asay()` at `:395` is suppressed under
`--auto`). So a **manual** run's output goes to that session's terminal and never reaches
`deploy.log`. RAN `grep -n "deploy.log\|postland" scripts/rotate-autonomy-logs.sh` → it rotates
`flakes.jsonl` and `runner.log` only (`:442-443`), **not** `deploy.log`; RAN `ls` → one unrotated
668 KB file. So the set-difference below is sound.

RAN (set join of `git reflog show HEAD | grep Fast-forward` targets against `deploy.log`'s
`deployed … → <sha>` targets):

```
launchd-logged unique targets:                                   103
reflog unique sha targets (window 2026-08-12 .. 2026-09-16):     152
launchd targets ALSO in reflog:                                   91
reflog targets NOT in deploy.log (= MANUAL / agent-run):          61   ← 40.1 %
launchd targets NOT in reflog (older than reflog window):         12
```

Plus **8** reflog entries of the form `merge origin/main: Fast-forward` (raw, ungated ff — the
path `hooks/validate-bash.sh:1352` denies), giving 160 total FF advances in the window.

**Independent corroboration of both the method and the number**: `.claude/commands/ship.md:124`
states the same attribution rule verbatim (*"`deploy.log` is not an attribution instrument … A
resolved-SHA ff with no `deployed` line in `deploy.log` is therefore a MANUAL `deploy-live` run"*)
and records its own measurement — **28 of 71 on 2026-08-24 = 39.4 %**, against my 40.1 % three
weeks later. Two independent measurements, same number.

**Conviction §1: 95 %.** Residual: I cannot distinguish an *operator* manual run from an *agent*
manual run from this evidence.

---

## §2 — The tier ladder, the budget, and which tier real advances come through

### 2.1 What each tier requires (READ, `scripts/deploy-live.sh:55-79`)

| Tier | Requires | Lag budget? | Loudness |
|---|---|---|---|
| **T1 VERIFIED** | newest **on-box GREEN** tree that is a **DESCENDANT of live HEAD** | none | silent |
| **T1H HERMETIC** | an **off-box** green over the hermetic subset **AND** no on-box RED (`:2160-2170`) | **none** — advances on positive evidence | bannered |
| **T2 DEGRADED** | T1+T1H empty **AND** lag past budget → newest commit carrying **no RED stamp** (`:2189-2201`) | **yes** — this is the whole gate | loud banner + a sha-keyed page |
| **T3 BLOCKED** | every commit above live HEAD is RED | n/a | refuse + page |

Budget (READ `:152-157`): `CC_DEPLOY_MAX_LAG_COMMITS` default **25**, `CC_DEPLOY_MAX_LAG_HOURS`
default **6**, whichever trips FIRST. Below budget the script prints the `waiting — …` line at
`:2318` and `exit 0`. Under `--auto` that line is **silenced** by `asay()`, so an in-budget wait is
literally invisible.

### 2.2 Which tier real advances come through — counted

RAN (join every reflog FF target against the stamp stores, comparing the stamp's own `ts` against
the reflog's advance timestamp):

```
advances whose target tree was ALREADY green at advance time (could be T1):   3   (2.0 %)
advances whose green stamp arrived AFTER the advance (NOT T1):               56
advances with no green stamp at all:                                         93
TOTAL sha-targeted advances:                                                152
```

```
advances carrying a T2 `deploy-degraded-<sha>.page`:  37   (pages are GC'd at 7 d —
                                                            CC_EVENT_TTL_DAYS, scripts/cc-gc.sh:53,391;
                                                            oldest surviving page 2026-09-09)
FF advances in that same retained 8-day window:       40   ⇒ 37/40 = 92.5 % T2
target tree carrying an OFF-BOX stamp (T1H-eligible):  3   (only 4 off-box stamps exist in total)
`HERMETIC deploy` banners in deploy.log:               1
`DEGRADED deploy` banners in deploy.log:             178
```

**So: T1 ≤ 2.0 % of advances; T1H ≈ 1–3 advances ever; T2 is ~92.5 % in the window where the
evidence survives, and 178 DEGRADED banners vs 1 HERMETIC in the log is the same story.**

### 2.3 "T1 is structurally unreachable" — VERIFIED, and the repo's *stated reason* is wrong

The repo asserts T1 is unreachable because the producer emits **0.17 greens/day**
(`scripts/deploy-live.sh:76`, and again in `.claude/settings.json:8 _why_converge`).

RAN, over the live stamp store (`~/.claude/autonomy/postland/stamps`, 629 stamps):

```
greens total: 86,  spanning 2026-07-30 .. 2026-09-03  (36 days)  ⇒ 2.39 greens/day
```

**The 0.17/day figure is refuted by ~14×** for the window where greens existed. But the
**conclusion survives on two stronger grounds**, both measured:

1. **Ordering, not rate.** 56 of the 59 advances whose target tree ever earned a green got it
   *after* the advance. A green that lands on a tree already live is by definition an **ancestor**
   of live HEAD, and T1 requires a **descendant** — so the green can never be a T1 target. The
   script's own wait-message says exactly this: *"the newest green on trunk is deeper still … and is
   an ANCESTOR of live HEAD — widening the scan would only surface it, never deploy it"*
   (`scripts/deploy-live.sh:2305`).
2. 🚨 **The green producer has been silent for 13 days.** RAN, all 629 stamps by day+verdict:
   last green **2026-09-03**; every stamp since is `red` or `cut`:
   `09-04: 6 red · 09-05: 6 red · 09-06: 5 red · 09-07: 4 red · 09-08: 6 red · 09-09: 3 red ·
   09-10: 5 red · 09-11: 5 red · 09-12: 5 red · 09-13: 1 red · 09-14: 5 red · 09-15: 6 red ·
   09-16: 5 red · 09-17: 2 red` — **58 reds, 0 greens.** Corroborated by
   `~/.claude/autonomy/postland/last-green` (content `24c598bac1c7`, mtime **Sep 3 11:23**).

So T1 is not merely rate-limited; **for the last 13 days it has had no eligible input at all**. And
T3 does not fire either, because most commits carry *no* stamp and `is_red` treats absent as
eligible — every advance falls straight through to T2's absence-of-evidence door.

**Conviction §2: 92 %.** Residual: the stamps dir may be GC'd, so historical green counts are a
lower bound; that only strengthens the 0.17/day refutation and does not touch the 13-day silence.

---

## §3 — Is there a post-land hook that converges? No. **This is the finding.**

- RAN `grep -nE "deploy-live\.sh" scripts/ship-land.sh` → `2437, 2480, 4173, 4205`, **all comments**.
  `:38` even states the design intent explicitly: *"and DEPLOY — not land — waits for the green
  verdict."*
- READ `post_release_finish()` (`scripts/ship-land.sh:1467-…`), the post-lock tail: backup-ref reap
  (`:1493`) and the stranded sweep (`:1497+`). No converge, no install.sh.
- RAN `ls -la .git/hooks/` → no `post-merge`/`post-receive`.
- `scripts/autonomy-sweep.sh`: 0 references.

**The chain a land actually starts is:** `ship-land` pushes → `postland-verify` (launchd, RAN
`launchctl list` → `98260  0  com.claude.postland-verify`, i.e. *currently running*) eventually
writes a stamp → **and nothing consumes that to trigger a deploy.** The deploy side only ever looks
at the world on its own 600 s clock, and only advances when the *budget* trips — never when a land
happens.

The nearest thing to a post-land actuator is `hooks/session-continue.sh:1097`, and it is **not an
actuator**: it is a Stop-hook `block` that hands the model the command as text, gated on the session
going **idle** with the budget already **breached**. By then the work has been inert for ≥6 h.

**Conviction §3: 97 %.**

---

## §4 — The real lag distribution

**Method (RAN):** from `git reflog show --date=iso HEAD`, take every `merge <sha>: Fast-forward`
(= a sanctioned advance) in chronological order. For each advance, every commit in
`prev_target..this_target` is a commit that *went live at that moment*; its **residency lag** is
`advance_time − commit_committer_time`. 151 advance intervals, **2 180 commits measured**.

```
seconds on trunk before going live:
  min=-6907   p25=1456    MEDIAN=8313    p75=22050   p90=57430   p99=127445   max=147879

hours:      MEDIAN = 2.31 h    p75 = 6.12 h    p90 = 15.95 h    p99 = 35.40 h    MAX = 41.08 h
```

(The negative min is a rebased commit whose committer date post-dates the advance — 1 of 2 180.)

**Batch size per advance** (RAN): `advances=151  commits=2180  min=1  MEDIAN=9  p90=28  max=110
mean=14.4`. A median advance carries **9 commits at once**, and the worst carried **110** — i.e. the
budget routinely lets a large block accumulate before releasing it.

**Advance frequency** (RAN, reflog FF per day): 1–8/day for 34 of the 36 days, spiking to **21** on
2026-09-16. Median ≈ 4/day against a trunk the repo characterises as ~63 commits/day.

### 4.1 Live state at the moment of this investigation

RAN in `/Users/chrisren/Development/claude-infrastructure`:

```
HEAD: 145c32f53  2026-09-16 23:49:16 -0500  docs(research): union-alpha drain routing — NO, …
git cherry origin/main HEAD  →  + 145c32f531398481f2fce2f5f1e23715f5b86b0d
behind origin/main: 3     ahead: 1
```

🚨 **The shared checkout is DIVERGED right now** — a commit was made directly in it ~13 minutes
before I sampled. `git merge --ff-only` cannot advance over that, so **every** converge path
(timer and manual alike) is structurally blocked fleet-wide until it is resolved. This is the
`LIVE_BREACH_WHY=diverged` / *"NO converge budget applies"* state (`scripts/wrap-ledger.sh:1869`).
It is a *live incident*, not a historical note, and it is orthogonal to the trigger question —
but it is the second-order cost of converging being manual: the same sessions that must converge
by hand are the ones committing in the shared checkout.

**Conviction §4: 90 %** on the distribution (the reflog is a complete record of advances but
`git reflog` expiry bounds the window to 36 days); **99 %** on the current diverged state.

---

## §5 — What a safe auto-converge-after-land would look like, and what is ALREADY permitted

### 5.1 What `.claude/CLAUDE.md` § "Standing-converge authorization" already grants an agent

READ, `.claude/CLAUDE.md` § Standing-converge authorization. Verbatim substance:

- An agent converges **its own just-landed, content-verified work without a fresh ask**, on the
  **degraded tier**, with exactly this command:
  `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`
- 🚨 **Never `--force`** — it takes the tip regardless of RED stamps and bypasses T1/T1H/T2/T3
  outright. The degraded tier *relaxes the CLOCK and keeps the EVIDENCE* (still no-RED, still runs
  `install.sh` so new files get symlinks, still banners + pages).
- **Not covered:** a bare `git merge --ff-only`/`git pull --ff-only` in the shared checkout (denied
  at `hooks/validate-bash.sh:1352`), `--bootstrap`, and any advance while the ladder reports
  T3/BLOCKED.

### 5.2 The paired permission rule EXISTS — and `deploy-live.sh`'s own header says otherwise (stale)

RAN `grep -n deploy .claude/settings.json`:

```
53:  "Bash(CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh)",
54:  "Bash(CC_DEPLOY_MAX_LAG_COMMITS=0 bash /Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh)"
```

Both **exact-match, no trailing `:*`** — so `--force`, `--bootstrap`, any other budget value and any
extra flag still prompt. The rationale is `.claude/settings.json:8 _why_converge`.

**But `scripts/deploy-live.sh:32-44` still warns** *"⚠️ AND THE LEVER ABOVE IS CURRENTLY DENIED TO AN
UNATTENDED AGENT … Until they do, an agent's real options are the bare form (which waits out the
budget honestly)"*. RAN `git log -S`:

```
a238afc5d  2026-09-16 00:02:16 -0500  docs(deploy-live): the lever … is denied to an unattended agent — say so beside it
8d551a4fd  2026-09-16 00:57:04 -0500  feat(converge): grant the agent the degraded-tier converge, exact-match and nothing wider
git merge-base --is-ancestor a238afc5d 8d551a4fd  →  true
```

**The header's warning is stale by 55 minutes.** A session that reads the script header (the most
likely place to look) will conclude the lever is denied and hand the operator a command — which is
the *exact* failure mode the surrounding comment block was written to prevent, now reproduced one
level up. This is a real, cheap, drivable fix: strike/annotate `:32-44`.

### 5.3 What a safe auto-converge-after-land looks like

The evidence above says the missing piece is **an edge trigger, not a new capability**. All four
safety properties already exist inside `deploy-live.sh`; only the *occasion* is missing.

Design, in the shape the repo's own rails already sanction:

1. **Trigger position: `post_release_finish()` in `scripts/ship-land.sh` (`:1467`), after
   `land-verify` has content-verified the push** — the same point that already discharges the
   rollback ref, i.e. the one place the script *knows* a real land happened and that its content is
   on trunk.
2. **The command is exactly the granted spelling** — `CC_DEPLOY_MAX_LAG_COMMITS=0 bash
   $REPO/scripts/deploy-live.sh` — never `--force`, never a raw ff. This is *already* the ladder:
   T1 → T1H → T2, still refusing on T3, still running `install.sh`, still paging a T2 advance.
   Setting the budget to 0 changes **only the clock**, which is precisely the knob the operator
   granted on 2026-09-15/16.
3. **Fire-and-detach, non-fatal.** A converge failure must never redden a completed land
   (`post_release_finish`'s existing `|| true` discipline at `:1493-1495` is the precedent). It
   should log its verdict where the lander's log already goes, not to the launchd `deploy.log`
   (which is the launchd job's attribution channel — polluting it would destroy the 1.3 measurement).
4. **Idempotent + serialised.** Two lands can finish seconds apart; `deploy-live` already
   fast-forwards to a target, so a second run is a no-op — but it should take the same lock
   discipline the tick uses (`~/.claude/autonomy/postland/run.lock.d` exists) so a converge cannot
   interleave with `install.sh` from the tick.
5. **The prerequisite that must be enforced first: refuse if the shared checkout is diverged or
   dirty.** As measured in §4.1, the checkout is diverged *right now*. An auto-converge firing into
   that state adds a refusal to every land instead of a converge, so the trigger must read
   `git cherry origin/main HEAD` and surface `⛔` rather than retry.

**Expected effect, quantified from §4:** replacing a 6 h/25-commit budget with a land-edge trigger
collapses the median residency lag from **2.31 h to ~0**, the p90 from **15.95 h**, and eliminates
the median-9/max-110-commit batching — because the advance would happen once per land instead of
once per budget expiry.

**What it does NOT fix, stated rather than hidden** (both already true of the timer, per
`.claude/CLAUDE.md` § Standing-converge authorization): a converge carries every *sibling* commit
below the target too, and it leaves the live tree **unstamped** until `postland-verify` catches up —
which, given §2.3's 13-day green drought, means indefinitely.

**Conviction §5: 88 %** on the design being safe and inside existing authorization; **99 %** on the
stale header at `:32-44`; **97 %** on the permission rule existing.

---

## §6 — Adversarial pass (what a hostile reviewer would check)

| Challenge | Checked | Result |
|---|---|---|
| "The timer is just dead — that's the whole story." | RAN `launchctl print` + counted `migrate:` lines | **Refuted.** 39 runs/7.56 h and ~94 runs/day long-window. The timer works; the *budget* is the gate. |
| "`deploy.log` is rotated, so your 61 'manual' advances are just lost launchd lines." | RAN `grep -n deploy.log scripts/rotate-autonomy-logs.sh` → rotates `flakes.jsonl`+`runner.log` only (`:442-443`); RAN `ls` → one unrotated file | **Refuted.** And `.claude/commands/ship.md:124` independently measured 28/71 = 39.4 % vs my 40.1 %. |
| "Maybe `postland-verify` or `autonomy-sweep` converges." | RAN greps | **No.** postland-verify only *writes stamps*; autonomy-sweep has **0** references. |
| "Maybe a git hook converges." | RAN `ls -la .git/hooks/` | **No** post-merge/post-receive hook exists. |
| "T1 unreachable is just repo folklore." | RAN stamp census | **Partly folklore, conclusion holds.** The cited `0.17 greens/day` is wrong by ~14× (real: 2.39/day while greens existed), but the ordering argument (56/59 greens arrive *after* the advance) and the **13-day zero-green drought since 2026-09-03** are stronger and independent. |
| "The agent lever is denied, so auto-converge needs an operator grant." | RAN `grep -n deploy .claude/settings.json` + `git log -S` | **Refuted, and it's a live doc defect.** The grant landed `8d551a4fd` 55 min *after* the header warning `a238afc5d` that still says it is denied. |
| "Nobody is converging, so lag must be huge." | RAN reflog residency measurement | **Refuted — and that is itself the finding.** Median lag is only 2.31 h *because humans/agents run it by hand 40 % of the time*. The manual work is what is hiding the gap. |

---

## §7 — The three sentences that answer the question

1. **What fires it after a land: nothing.** `ship-land.sh` has zero invocations (four comments), no
   git hook exists, `autonomy-sweep.sh` has none; the only automated caller is a 600 s launchd
   clock that is alive and delivering at 65–86 % of declared rate.
2. **Why converging is manual: the clock advances only on budget expiry (25 commits / 6 h), a land
   signals nothing, and the T1/T1H "verified" doors are shut** — T1 ≤ 2.0 % of advances, T1H ≈ 1,
   T2 ≈ 92.5 %, and the green producer has emitted **0 greens in 13 days**. So **61 of 152 advances
   (40.1 %) were run by hand**, and the healthy-looking 2.31 h median lag is *purchased by that
   manual labour*, not by the timer.
3. **The fix is an edge trigger, not a new capability** — `post_release_finish()` firing the
   already-granted `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, guarded on a
   non-diverged checkout; and `scripts/deploy-live.sh:32-44` must be corrected first, because it
   still tells every reader that lever is denied.
