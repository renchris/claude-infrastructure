---
status: open
---

# MASTER: account facts — which account, which model, and whether it can still authenticate

**Condition key:** `master-account-facts` · **Live members 2026-08-12 (measured after the apply):** 27 (18 open · 9 blocked)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-account-facts" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** Every routing decision in the fleet reads these facts, so an error here is
never local: a stale `providers.json` row, an account whose CLI→GitHub link is missing, a router that
is built and landed but NOT WIRED. And the facts have a hard property the rest of the store does not —
**they perish.** A grant can die long before its quota resets, and only a new `/login` moves the login
cliff, so any conclusion cached about an account is wrong by default and must be re-measured.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

🚨 **SUPERSEDED FOR THE LOCAL DRAIN (2026-08-13): read every `S` below as `T`.** This table was
authored under the one-session-per-wave model. The non-cloud backlog is now worked by THE LOCAL DRAIN —
a single standing session whose entire purpose is that it occupies **one** of the ~15 concurrent slots
for its whole life (`BACKLOG_SELF_DRAINING_2026-08-12.md:392`: *"One slot, indefinite duration — because
the bottleneck is concurrent sessions (~15), not session length"*). Firing a dispatched session per wave
spends a second slot and defeats the mission. Work every wave with **teammates INSIDE the drain session**
(`Agent({name})`, worktree-isolated, ≤150-line briefs, each torn down with a structured
`shutdown_request` — a plain-text broadcast leaves an orphaned pane and worktree), and recycle at the
EFFORT boundary via `handoff-fire.sh --recycle` — same pane, fresh context, no new slot. The `S` markers
below are left in place as the historical record of how these waves were originally scoped.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **A1 · router + start latency** | **S** | `claude1` pins account 1, bare `claude` auto-routes, start cost cannot regress | — |
| **A2 · auth durability** | **S** | a forced logout is RECORDED; the refresh herd stops losing races | — |
| **A3 · provider surface** | **S** | MCP / multi-provider / adversarial-slot facts are current and probed | — |
| **A4 · the skills fork** | **S** | the 19 untracked skills have a tracked source | — |

**Lead context budget:** ≥50%. **Succession point:** after A1 — it is the one the operator feels, and
it is the largest single sub-wave.

## Sub-waves

### A1 · Router + start latency (the operator-visible one)
The interactive account router is **built, tested and landed but NOT wired** — wiring it edits
`~/.zshrc`, which is why it stalled (that row is `master-operator-gated`; coordinate rather than
re-deciding). The measured start-time terms: `SessionStart` burns 5 s per launch on a function that is
killed and returns EMPTY; ~~`probe_provider` is 4.31 s of a 4.37 s warm `claude-accounts --json`~~
**DONE 2026-08-15, `fb1ea5d43`** — re-measured at 3.68 s of 3.7 s, same shape; warm `--agents` is now
0.068 s against 3.24 s cold. Only the CHILD PROCESSES are memoised: a whole-probe cache reds the
pin-proof test, and keying on `providers.json` alone (the invalidation the row proposed) reds the
binary-identity test; `claude-accounts collect()` can go 2,480 ms → 340-674 ms with a
5-way parallel — still open, and it is START_LATENCY_ROUTER Follow-on #1. Also here: the router's KMAX keys on RESIDENT rather than ACTIVE sessions, so one
integer refuses the 33rd session.

⚠️ **A config flip is not a shell flip** — a new launcher name exists only in shells started AFTER the
rc change, so pin it via an env prefix when verifying (memory: `config-flip-is-not-a-shell-flip`).

### A2 · Auth durability
~~**No instrument records a forced logout** — build the per-account auth-state time series~~ **BUILT.**
The instrument is `tools/auth/auth-timeseries.sh` (127 lines, on trunk), whose own line 2 names the
row it satisfies. Row `f272b30e66f5` closed 2026-08-15 as superseded by the activation row
`e848943a81f4`.

🚨 **"built + wired but NOT armed" is HALF FALSE, and the false half is the dangerous one.** Measured
2026-08-15: `launchctl list` shows `com.claude.auth-timeseries` **LOADED**, last exit **126**, and
`~/.claude/logs/auth-timeseries.err.log` holds **468 failures** of `cannot execute: No such file or
directory` for `~/.claude/scripts/auth-timeseries.sh`. The label IS armed; what is missing is the
SYMLINK. `tools/` is not a deployed dir, and the only thing that creates that link is
`docs/activation/pending-activation/35-auth-timeseries-activate.sh` — which **refuses to arm if it
cannot make it**, and whose plist says in as many words *"Do not bootstrap this label by hand without
creating the link first."* So the guard was bypassed, and the job has looked armed while recording
nothing since. Filed as `85fc4f3216a7` with the runnable activation. *Existence evidence from a
DECLARATION is not evidence of success — `launchctl list` showing a label says nothing about whether
it runs.*

The oauth refresh
herd is a losing race: jitter the refresh within an account and let `heal()` run with live sessions.

🚨 **That second clause is an AUTH ESCALATION, not agent work, and it may be self-defeating.** "Let
`heal()` run with live sessions" is the deletion of a documented rotation-safety invariant at
`bin/claude-accounts:709-711` — *"a refresh racing a running CC can rotate the token out from under
it, and a discarded rotation means logged out"* — which was **hardened, not relaxed** (an unmeasurable
`ps` now refuses too, because "I could not look" is not "there is nobody there"). Its failure mode is
precisely the mass logout the row exists to prevent. Blocked on an operator ruling (`66be078a3f50`).
The jitter half IS agent-safe — and measured, there is **no jitter anywhere** in `bin/claude-accounts`
today — but tuning a herd wants the time series first, so the sequence is: activate the recorder,
measure, then decide the invariant.
`next2` carries a `.linked` marker but cannot create and falls back to bundle mode. A PARITY GUARD row
names two hand-copied implementations (`cc-relogin live_sessions()` vs `claude-accounts concurrency()`)
that must not drift.

### A3 · Provider surface
`providers.json`'s `pi-codex` row is STALE on the live layer (the fix landed and is not live — that is
`master-convergence-deadlock`'s chain, not a second bug). MULTI-PROVIDER PLANS, MCP MEMORY 100P, and
the CODEX ADVERSARIAL SLOT PROBE (certify or reject `gpt-5.6-sol`) are the design rows. The Fable probe
fails on ALL FOUR accounts with an undocumented signature.

⚠️ **A version claim is about the running process, not the launcher** — `ps -o command= -p $PPID`, never
a launcher's `--version` (memory: `version-identity-is-the-running-process-not-the-launcher`).

### A4 · The skills fork
~~19~~ **18** skills live in `~/.claude/skills` with no tracked source: untracked and unlandable.
~~and forked across the four config dirs~~ — **the FORK half is REFUTED, and it was the half that made
this urgent.** Measured 2026-08-15: every other config root's `skills/` is a **symlink to
`~/.claude/skills`** (`.claude-next`, `-secondary`, `-tertiary`, `-quaternary`), and `SKILL.md`
reaches **inode 362553914 through every path**. There is ONE copy on disk, so an edit cannot fork
what does not exist twice — and `diff -rq` reporting all 18 identical is trivially true because they
are the same file. *A duplication claim has to be measured on inodes, not on paths.* The untracked
half holds, with drift: `cc-version-audit` has since been tracked (19 → 18).

The fix is a tracked source plus the parity mechanism from
`master-enforcing-store` E1 — do not build a second one.

🚨 **And landing the sources WITHOUT converging the live layer would CREATE the fork this row wrongly
claimed** — a tracked copy plus an untracked live copy is two files where there is currently one.
`install.sh:598-608` already does the right thing (for each skill name present in the repo it makes
the live dir real and links each file into the checkout, leaving unknown skills untouched), so
**tracking and symlink conversion are ONE operation, not two.** Remaining work is 18 judgment calls
over 768 KB — dominated by `react-best-practices` (296 KB / 59 files), `pyramid-principle-full`
(116 KB / 11), `outlook-cleanup` and `frontend-design-vue` (84 KB each) — and the row itself allows
"declare local-only IN the skill" as a valid disposition, which is the right answer for the vendor
corpora and for `pyramid-principle-full`, a distillation of a copyrighted book. Row `3e2358f03e23`
now carries a falsifier that exits 0 only when every live skill is either tracked on origin/main or
declares itself local-only.

#### The triage decision, made 2026-08-15 — execute it, do not re-derive it

**DECLARE LOCAL-ONLY (5).** Third-party or copyrighted content whose value is the corpus, not our
authorship; tracking them would put someone else's text in this repo's history for no gain:
`react-best-practices` (296 KB / 59 files, a vendor rules corpus) · `vercel-design-guidelines` ·
`motion` (the Motion codex, 10 files) · `pyramid-principle-full` (116 KB / 11 files) and
`pyramid-principle` — both distillations of a copyrighted book via the `corpus-to-skill` pipeline.

**TRACK + SYMLINK (13).** Our own authorship, small, and exactly what "untracked, unlandable, no
`/ship` path, invisible to deploy-parity-assert" is about: `agent-browser` ·
`autonomous-authenticated-web-access` · `beautiful-mermaid-docs` · `corpus-to-skill` · `dia-agent` ·
`frontend-design-vue` · `frontier-campaign` · `frontier-hole` · `frontier-run` · `grok-wiki-cli` ·
`grok-wiki-custom` · `model-upgrade` · `outlook-cleanup`.

🚨 **THE TRACK HALF IS BLOCKED, AND BOTH BLOCKERS WERE MEASURED — do not attempt it until they
clear.** Tracking without the symlink conversion CREATES the fork this row wrongly claimed, and the
only thing that converts is `install.sh`:
1. `install.sh` **REFUSES a global install from a linked worktree** (`install.sh:38-81`) — which is
   where the drain session works — because a worktree "is entitled to be deleted" and pointing the
   live layer at one would be the catastrophe the guard exists to prevent.
2. The shared checkout, the only non-worktree place it could legitimately run, is **62 commits
   behind `origin/main`** (1 ahead), so installing there copies pre-trunk content into `~/.claude`
   while printing success — the 2026-08-01 failure that same guard was built for.

So this is the convergence deadlock again (`3df911c0470e`), not a second problem. The declare-half
needs neither install nor convergence and can be done at any time; it shrinks the falsifier's count
from 18 to 13 without closing the row.

## Definition of done
Every account fact the fleet routes on is produced by a probe that runs on a schedule and records that
it ran; the router is wired; a forced logout appears in a time series rather than in a surprise; and no
skill or provider row is enforced from an untracked file.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 22 rows on this condition
  (5 pre-existing from the 2026-08-09 triage, 4 by its verdict replay, the rest semantic).
- **2026-08-15 — THE LOCAL DRAIN recycle #9 worked this condition: 16 open → 7.** Four rows landed or
  driven to a verdict, four blocked on operator calls the rows themselves named, one duplicate folded.
  Landed: `d1068fdf9b6a` (provider-probe memo, `fb1ea5d43`), `e9245cc24dff` (the cost guard's leading
  indicator, `bfe2b5daf`), `1d20ff5ee344` (the qos-rewrite narrowing, `27772ede4`). Refuted and closed
  on re-measurement: `37a0b651bcce` — the two eval-bin spellings both live on trunk, but the second is
  a thin DELEGATOR, not a rival implementation, and four tests in
  `tests/account-fact-derivation.bats` pin the agreement. Closed as built: `f272b30e66f5`. Folded as a
  duplicate of `48e14163e78a`: `492b95cbac72`, whose five items are the START_LATENCY_ROUTER shipped
  table plus its Follow-on #1.

  **Three methodological notes this wave paid for, all of the same family — an instrument that
  answers a question you did not ask:**
  1. The handoff said these rows carry no falsifiers. **Six do.** Five answer "still live" by printing
     NOTHING and exiting 1, which reads exactly like a broken probe — `plan-phase-scan.sh` prints the
     affirmative token `FALSIFIED` only on success, deliberately, so an older deployed copy cannot
     forge a retraction. **Read a probe's contract before calling it broken.**
  2. `37a0b651bcce`'s falsifier asked whether a BRANCH landed. The fix had landed by another route, so
     branch-ancestry could only ever say "live". Likewise `492b95cbac72`'s plan cites five shas that
     all RESOLVE but are **not ancestors of origin/main** — pre-rebase — which is why every landedness
     claim here was settled by CONTENT (`git show origin/main:<path>`), never by ancestry or count.
  3. The first reproduction probe for `1d20ff5ee344` was **VACUOUS and said the opposite**: its command
     text contained the string `cc-bats`, which trips that hook's own idempotency guard, so the probe
     disabled the mechanism it was testing. Its control proved the file was written and nothing about
     the rewrite.
