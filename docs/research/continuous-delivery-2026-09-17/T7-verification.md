# T7 — Proving a RUNNING session executes the LANDED bytes

Repo: `/Users/chrisren/Development/claude-infrastructure` (read-only; nothing in the repo was modified).
Date: 2026-09-17. All `RAN` blocks are real output from this session.

## 0. The headline, first

**There is no check on this box that proves a running process is executing the landed bytes.**
There are four checks, and they form a chain of four *different* claims, each of which is
silently taken as the next one:

| Rung | Claim actually proven | Proven by | Blind to |
|---|---|---|---|
| **L1 ref** | trunk carries the commit | `git ls-tree` / `merge-base` | everything below |
| **L2 checkout** | the SHARED CHECKOUT's ref carries it | `wrap-ledger` `LIVE_LAG` / `LIVE_DIVERGED` | whether any symlink exists |
| **L3 filesystem** | `~/.claude/<path>` exists and (for 3 of 22 classes) has the right bytes | `deploy-parity-assert.sh`, `LIVE_ADDS`, `LIVE_STALE` | whether anything re-read it |
| **L4 process** | 2 daemons' argv-named file has not changed since they started | `deploy-live.sh residency_report` | every other process; every library; in-memory state |

Nothing above L4 exists. And **L4 covers 2 processes out of the whole box** (measured below), does
not cover Claude Code sessions at all, and compares an *mtime*, not content, and compares it
against the **live layer**, not against **trunk** — so every L4 verdict is conditional on L2/L3
being true, which is exactly the assumption that failed on 2026-09-04.

**Conviction that "it is live in the running session" is currently an ASSUMED claim, not a checked
one, for every artifact class except the 2 resident daemons: 96%.**

---

## 1. `deploy-parity-assert.sh` + `tests/deploy-parity-live.bats`

### What they compare

`scripts/deploy-parity-assert.sh` has four legs, all of them **CHECKOUT ↔ LIVE**:

1. **`~/bin` strict** (`:109-111`) — `claude-accounts` must be a *symlink into the repo*.
2. **`~/bin` copy** (`:111`, 4th leg at `:1100`) — `claude-latest|claude-update|claude-versions|claude-kimi`
   compared **by content**; a difference is drift, never a hard error.
3. **Existence leg** (`:425-1030`) — for each of 22 install.sh deploy classes, does
   `~/.claude/<rel>` exist? `-e`, which follows symlinks.
4. **Provenance leg** (`:28-36`) — did the shared checkout reach its commit *through deploy-live*,
   and does the tree carry a GREEN stamp?

`tests/deploy-parity-live.bats` is 2 tests and 86 lines. It asserts the assert exits 0 (skipping on
its exit-3 no-verdict, `:50`) and that the assert agrees with itself invoked through a deployed
symlink (`:67-86`). It asserts **nothing about any process**.

### RAN — the assert, on this host, now

```
$ CC_PARITY_FILE=0 bash scripts/deploy-parity-assert.sh   → rc 1
  LINKED    claude-accounts        → repo (cannot drift)
  OK        claude-latest/update/versions/kimi   copy identical to repo
  UNGATED   (provenance)           HEAD advanced OUTSIDE deploy-live
  UNVERIFIED (verification)        HEAD tree 50c8972809b4… has NO green stamp
  class parity … 22 rows, all `ok`, 0 missing   (agents 4/4, hooks 87/87, scripts 203/203, …)
```

### The drift classes it CANNOT see

**(a) It never compares the checkout to TRUNK.** Every leg's left operand is `$REPO` = the shared
checkout (`:50-103`). Measured at the same moment as the run above:

```
$ git rev-list --count HEAD..origin/main   →  3
```

So "0 missing across all 22 classes" is true **of a checkout 3 commits behind trunk**. At a lag of
70 the same 22 rows read identically. This is precisely the `🚀 landed ≠ live` split the global
rules describe, and the parity assert is structurally blind to it — by design (it is the *parity*
auditor, not the *lag* auditor), but the output does not say so.

**(b) For 19 of 22 classes it checks EXISTENCE, not IDENTITY.** Only the `root SSOT (link)` class
resolves the link target and compares bytes (`:918-960`). Its own comment states the scoping
decision: *"Scoped to this class deliberately, not widened to every class above: a symlink CANNOT
drift"* (`:909`). That premise is true of link *contents* and silent about link *targets* — a
`hooks/foo.sh` symlink pointing into **a different checkout** or a stale worktree passes as `live`.

RAN — the check that does not exist:

```
live links scanned=523  into-shared-checkout=518  elsewhere=5
  bin/claude-search             -> …/claude-session-search/bin/claude-search
  bin/session-index-backfill.sh -> …/claude-session-search/scripts/…
  bin/session-index-chunk.py    -> …/claude-session-search/scripts/…
```
Today all 5 exceptions are the documented SECOND-INSTALLER class (`:681-690`). Nothing in the
repo verifies that; I had to hand-roll it. The corpus already records the cost of this exact
shape — `[Symlinked $0 splits sibling sources]`, where a live-layer invocation sourced *another
repo's* copy of a shared library.

**(c) It sees no process.** There is no residency leg in the parity assert. A daemon 23 h stale,
a kitty with a sticky override, a Claude session started before the land — all score `ok`.

**(d) Its `MISSING`/class table is per-CLASS, which is the fix for an older blindness but still
per-FILE-EXISTENCE.** The corpus' `LIVE_ADDS` note records the class of failure it *does* catch:
five landed runtime files absent from the live layer, which this assert saw (5 MISSING) while
`wrap-ledger` read 0.

**FAIL-SAFE FLAG (1) — resolved, worth recording as the model.** `:96-103` is the one place this
file refuses to fail safe: an unresolvable `$REPO` exits **3**, not 0, because every leg below
`SKIP`s what it cannot find and would otherwise print one SKIP line and return 0 — "indistinguishable
by exit code from real parity". That is the correct handling of the exact defect flagged at §3 below.

---

## 2. `wrap-ledger.sh` LIVE_* fields

READ, `scripts/wrap-ledger.sh`:

| Field | Definition | Line |
|---|---|---|
| `LIVE` | 1 iff the live layer is verified at/above HEAD | 1132-1134 |
| `LIVE_SRC` | `ok · behind · n-a · unknown · skip` — origin URL compared **byte-equal** | 1403-1415 |
| `LIVE_LAG` | `git -C $LIVE_REPO rev-list --count HEAD..$TRUNK` — the shared checkout's DISTANCE | 1174, 1442 |
| `LIVE_STALE` | of the paths the lag changes, how many are reached by a live link AND differ in content | 1238-1261, impl 1494-1520 |
| `LIVE_ADDS` | paths ADDED between the delivered sha and trunk, surviving two suppressors | 1149-1231, impl 1572-1600 |
| `LIVE_ADDS_BASE` | which denominator was used: `advance` · `live-head` · `none` · `?` | 1232-1237 |
| `LIVE_DIVERGED` | commits live HEAD carries that trunk does not — converger BLOCKED, no budget | 1262-1284 |
| `MIG_FAILED` | count of failed-migration records | 1286-1294 |

### The denominator question

`LIVE_ADDS` is measured **from the sha `deploy-live` last actually DELIVERED** —
`$POSTLAND_DIR/deploy-last-advance`, read at `:1586-1591` — to **TRUNK** (`:1594-1598`), with a
fallback to `LIVE_SHA` recorded in `LIVE_ADDS_BASE=live-head`.

**Why re-keyed (wrap-ledger.sh:1153-1170, and yes to the question asked):** the old left operand
was `LIVE_SHA` = `git -C $LIVE_REPO rev-parse HEAD`, the shared checkout's ref — **which any
fast-forward moves**. deploy-live's own §2.E path B advances FILES and creates NO symlink. So the
fast-forward drives `LIVE_LAG` to 0, EMPTIES the `LIVE_SHA..HEAD` window, and `LIVE_ADDS` reads 0
— *the remedy-shaped event extinguishes the alarm without doing the remedy.*

The file records this as a measurement, not an argument (`:1163-1170`):

> At 2026-09-04T02:28:45Z this ledger read `RUNG=✅ LIVE_LAG=0 LIVE_ADDS=0` while five tracked
> runtime files landed on trunk had NO live counterpart — `bin/cc-lid`,
> `commands/keep-laptop-alive.md`, `hooks/lib/memory-index-locate.sh`,
> `hooks/memory-index-drain.sh`, `scripts/memory-fleet-sweep.sh` … Both shipped auditors saw them
> (deploy-parity-assert: 5 MISSING; deploy-link-parity: 5 UNLINKED, rc 1). Running the sanctioned
> converge made all five live; **this field read 0 BEFORE and 0 AFTER.**

**So: yes.** A fast-forward that creates no symlink drove the lag to 0 while delivering nothing, and
that is the exact incident in the brief. `deploy-last-advance` cannot be moved by anything but a
converge that actually ran, which is why it is the right denominator.

The **right** operand was ALSO wrong and was fixed in the same pass (`:1172-1182`): it used
`$HEAD_SHA` — the *session's* HEAD — so `git merge --ff-only origin/main` **in a worktree** moved
`LIVE_ADDS` 2→3 while the live layer was byte-identical on both sides and both other auditors read
the same numbers. One field, drivable in both directions, by events that touch nothing it reports on.

### The two suppressors, and the named residual

`:1573-1583` — a path is suppressed if (a) its top-level is not one the live layer actually
deploys (`_live_tl_deployed`, `:1365-1390`, derived from the live layer's OWN links, never a typed
list) and further narrowed by `_live_class_deployed` (`:1347-1364`), which **extracts and executes
`deploy-parity-assert.sh`'s own `case "$rel" in` block** rather than copying it; or (b) the path is
already present under `$LIVE_ROOT`.

Both fail **OPEN** — an unreadable arbiter simply does not narrow (`:1338-1343`, `:1353`). That is
the correct polarity for a suppressor and is stated as such.

**The residual is named in the code** (`:1194-1199`): a genuinely NEW deployed top-level has no
link yet, so its adds are wrongly exonerated. `deploy-parity-assert` remains the auditor of record
— at 24.35/24.94/25.07 s against wrap-ledger's 0.32 s, so it is not callable from the close path.

### `?` is a first-class state, and this is the anti-fail-safe discipline done right

Every arm — `LIVE_ADDS`, `LIVE_STALE`, `LIVE_DIVERGED` — renders `?` rather than 0 when an operand
does not resolve, because **0 is the healthy value** and a swallowed failure "would be
indistinguishable from a fully-converged box" (`:1240-1245`, `:1601-1605`). The `_bounded` rc is
captured rather than `|| true`'d, after backlog `4fe8d531ce68` measured a timed-out sensor
manufacturing the ✅ the arm exists to forbid.

### What LIVE_* still cannot say

- `LIVE_STALE` compares the **far end of a live link** to **`$HEAD_SHA`'s blob** (`:1508-1512`) —
  the session's HEAD, not trunk. Its own header concedes this: *"HEAD is ours by construction."*
- No LIVE_* field observes a **process**. All seven are functions of two refs and a filesystem.
- `LIVE_STALE`'s scan is over paths the *lag* changes, so a file made stale by something other than
  the lag (a hand-edit in the checkout, a reverted worktree) is outside its population.

---

## 3. The residency check — the closest thing to L4

### RAN, live, this session

```
$ bash scripts/deploy-live.sh --dry-run --offline
deploy-live: kitty-reload: verdict=unchanged key=5d6aad4bca34
deploy-live: residency: 2 of 2 executing resident daemon(s) are running current bytes · 1 exempt (argv names no file on disk)
deploy-live: waiting — no GREEN stamp among the newest 200 commits …; lag 3 commit(s) / 0h14m, inside the degrade budget (25 / 6h)
```

### How it decides

`scripts/deploy-live.sh:1800-1857` → `scripts/lib/cc-common.sh:111-180`.

1. **Population** = plists whose *own top-level* `KeepAlive` key is literally `true`/`1`
   (`cc-common.sh:111-115`). RAN: **3 of 26** plists qualify — `caffeinate-floor`,
   `compressor-sentinel`, `lead-supervisor`. The comment records why not `grep -l KeepAlive`: that
   matches 6, three of them in PROSE, two of those saying the job is deliberately not KeepAlive.
2. **PID** from `launchctl list <label>` (`cc-common.sh:167-180`).
3. **Program** = the **last token of the running process's own argv that is an existing file**
   (`cc-common.sh:124-133`). Never from the plist — 4 plists are `/bin/bash -c '<inline>'` with
   `$HOME` unexpanded.
4. **Verdict** = `stat -L -f %m <prog>` **>** the process's `lstart` parsed under `TZ=UTC LC_ALL=C`
   (`cc-common.sh:152-166`). `-L` follows the live-layer symlink into the checkout; without it the
   probe read a 23-h-stale daemon as fresh.
5. **Exempt** = `resident_program` returned empty, i.e. argv names no file on disk
   (`deploy-live.sh:1838-1840`). RAN: that is `caffeinate-floor`, whose argv is `caffeinate -i -s`.
   It is *counted and reported*, not silently dropped — good denominator hygiene.

RAN — I re-derived both verdicts by hand:

```
pid=9749 /Users/chrisren/.claude/scripts/compressor-sentinel.sh
  start=2026-09-16 17:31:10   file_mtime=2026-09-16 17:21:42   stale=NO
  live sha256 7f9dcd01adfd85ed == HEAD == origin/main
pid=1094 /Users/chrisren/Development/claude-infrastructure/scripts/lead-supervisor.sh --daemon
  start=2026-09-16 16:29:12   file_mtime=2026-09-10 23:45:21   stale=NO
  live sha256 b5456e08e62553c8 == HEAD == origin/main
```

Both genuinely current today. The verdict was right; the *reasoning* only proves "not modified
since start".

### Assessment — how strong is it, really

**Strengths (real, and better than they look):**
- It reads the **RUNNING** image out of argv rather than the plist — the one thing that makes it an
  L4 probe at all.
- It fails to **NO VERDICT** (not to healthy) on two axes the naive version got wrong: lib
  unreadable (`deploy-live.sh:1806-1808`), and lib **present but predating the probes**
  (`:1816-1830`) — a measured incident where a `-r` test passed, the source succeeded, and the loop
  emitted 26 `command not found` lines and concluded "no resident daemon is executing" over a host
  with two stale daemons.
- Damping is on a **dedicated signature marker** and re-arms on health (`:1780-1797`), so
  recovery→re-failure is loud on the next tick.

**Weaknesses, in descending severity:**

**(W1) 🚩 FAIL-SAFE DEFAULT THAT MATCHES THE HEALTHY OUTPUT.** `resident_image_stale` returns **1
(= NOT stale)** on any operand it cannot resolve (`cc-common.sh:159-161`): a `ps` that returns
nothing, an unparseable `lstart`, a `stat` that fails. Non-stale increments nothing, so the run
renders `residency: N of N … running current bytes`. The comment calls this "fail-closed", and it
is — *against an unwanted bounce*. Against the **verdict** it is fail-OPEN, and it is the only arm
in this file that lacks the `?`/NO-VERDICT state that `residency_report` uses two layers up and
that `wrap-ledger`'s LIVE_* arms use throughout. Unfalsifiable by the brief's own test: an
instrument failure and a healthy box print the identical line. **Conviction this is a real defect:
92%** (the 8% is that an operand failure here is rare and the wrong-direction bounce is genuinely
costly — but the cure is a third state, not the current silence).

**(W2) It compares against the LIVE LAYER, not against TRUNK.** `stat -L` resolves the symlink into
the shared checkout, which at this moment is 3 commits behind. A daemon started *after* a stale
file was written reads **fresh** while executing pre-trunk bytes. Residency is therefore *transitive
on L2/L3 being true* — the assumption that failed on 2026-09-04. Today it happens to hold (I
verified content equality by sha above); nothing checks that it holds.

**(W3) mtime is not content.** A `git checkout` / ff that rewrites a file with identical bytes bumps
mtime → false STALE (safe). The unsafe direction: any process that re-exec'd or reloaded after start
reads stale forever (noise), and a file whose mtime is older than start but whose *content* is wrong
reads fresh (W2's mechanism).

**(W4) One file per process.** `resident_program` returns **one** path. `lead-supervisor.sh` sources
libraries at runtime; none of them is compared. A daemon whose entry point is untouched while five
sourced `hooks/lib/*.sh` changed reads `current bytes`.

**(W5) `resident_program` picks the LAST existing-file token in argv, which need not be the
program.** `/bin/bash /x/foo.sh --out /tmp/bar.log` resolves to `bar.log`. That is a false NEGATIVE
path (a constant data file reads fresh forever while the script rots) as well as a noise path
(a log file whose mtime always moves reads stale forever). No current plist hits it — all 3 have
clean argv — so this is latent, not live. **Conviction it is reachable by the next plist added: 60%.**

**(W6) The population is 3 of 26 plists, 2 checked, and 0 Claude Code sessions.** A `RunAtLoad` /
interval job re-execs each tick and is fresh by construction, which is why it is excluded — correct.
But the brief's subject, "a running session", is in no population anywhere on this box.

**(W7) Detection without actuation.** The remedy runs only on an advance **and** only with
`CC_INSTALL_RESIDENT_RELOAD=1`, which is **unset by default** (`install.sh:1109-1110`). So a true
STALE verdict is a log line whose repair nobody performs automatically.

**Overall: residency is the only honest L4 probe in the repo, it is well-built for the population it
names, and its population is ~2 processes. Strength as a general proof that the box runs landed
bytes: LOW. Conviction: 90%.**

---

## 4. Does anything check that a RUNNING kitty has the current `kitty.conf`?

**No. There is an ACTUATOR and there is no VERIFIER, and the actuator's success verdict is a claim
about signal delivery.**

### What exists

`bin/cc-kitty-reload` (169 lines), called by `deploy-live.sh` `kitty_config_reload()` (`:1877-1897`)
on every tick and through `--would` on `--dry-run`.

- **Content key** (`:93-102`): sha256 of the concatenated contents of every `*.conf` under
  `~/.config/kitty`, `cat`'d so symlinks are followed.
- **Compare against a stamp** (`:113-119`): equal ⇒ `verdict=unchanged`, silent no-op.
- **Actuate** (`:155-158`): `kill -USR1` on each live kitty pid.
- **Stamp advances** only if every signal succeeded (`:160-167`).

RAN, twice, agreeing:
```
$ bash scripts/deploy-live.sh --dry-run --offline
deploy-live: kitty-reload: verdict=unchanged key=5d6aad4bca34
$ (recomputed by hand over ~/.config/kitty/*.conf)
5d6aad4bca34c1546375e4b262f1bba0a585816087f1f271dd29707b17aa8e66
$ cat ~/.claude/autonomy/kitty-config-deployed
5d6aad4bca34c1546375e4b262f1bba0a585816087f1f271dd29707b17aa8e66
```

And kitty's own watcher is alive — RAN:
```
$ /bin/ps -axo pid=,comm=  (basename == kitty)      → 73832  /Applications/kitty.app/Contents/MacOS/kitty
$ /bin/ps -axo pid=,command= | grep __watch_conf__  → 74784  kitten __watch_conf__ 73832 100 \
      /etc/xdg/kitty/kitty.conf /Users/chrisren/.config/kitty/kitty.conf
$ readlink ~/.config/kitty/kitty.conf → …/claude-infrastructure/config/kitty.conf
$ cat ~/.claude/autonomy/kitty-title-state → off
```

### Why none of that is verification

**The stamp is a fact about the FILE and the last signal round.** After a successful reload it
equals the file hash forever, so every later tick reads `unchanged` and touches nothing. If the
running kitty's in-memory state diverges *after* that point — which is exactly the sticky-`-o`
case — the tool is by construction silent. `verdict=unchanged` is the output in BOTH the healthy
state and the diverged state.

**🚩 FAIL-SAFE FLAG (2) — `no-instances` advances the stamp on a failed census.**
`bin/cc-kitty-reload:121-132`: `live_kitty_pids` empty ⇒ write the stamp, `verdict=no-instances`,
exit 0. The justification (`:62-63`) is sound for the genuine case — a kitty started later parses
the file itself. But an empty census is also what a broken `$PS_BIN`, a changed `ps -o comm=`
format, or a `comm` that is not exactly `kitty` produces. Those are indistinguishable, and this
one **latches**: the stamp advances, so the next tick reads `unchanged` and the reload is never
retried, while every live kitty runs the old config forever. `tests/cc-kitty-reload.bats:85` pins
the advance as intended behaviour; there is **no case for a census that could not run**.
Conviction this is a real hole: **88%**.

**🚩 FAIL-SAFE FLAG (3) — `kill -USR1` rc 0 is signal DELIVERY, not reload.** `:157` counts `ok`
on the kill's exit status. Nothing reads back whether kitty parsed, whether it errored, or whether
the new values took. `verdict=reloaded instances=N` is the strongest statement the tool makes and
it is one rung below the claim a reader takes from it.

**The sticky-override class, which the brief names, is structurally invisible to all of it.**
`scripts/kitty-pane-title-toggle.sh:80-93` records the mechanism and the A/B:

> `kitty @ load-config` RESPECTS overrides from the kitty invocation AND from a PREVIOUS
> load-config, by documented design, unless `--ignore-overrides` is passed … MEASURED on the
> operator's live kitty (pid 97084, 12 panes), one variable, rows via `kitty @ ls`:
>   without the flag … `[8,8,8,8,8,45,45,45,45,47,47,47]` (identical — inert)
>   with    the flag … `[7,7,7,7,7,44,44,44,44,45,45,46]` (the bar drew)
> That instance was launched with NO `-o` in its argv, so the sticky override came from an earlier
> load-config, not from startup — which is why nothing about the process looked wrong.

Two consequences nobody has written down:

1. **`cc-kitty-reload` cannot clear this class.** Its actuator is SIGUSR1, and kitty's SIGUSR1
   reload re-applies the same override set — there is no `--ignore-overrides` for a signal. So the
   repo's own reload path preserves precisely the state that makes the landed config inert.
   *(READ + inference from kitty's documented load-config semantics as quoted above; NOT measured
   here, because measuring it means a `load-config` against the operator's live windows. Conviction
   85%.)*
2. **The per-window scope is a second one.** `reconcile_spacing` (`:147-153`) exists for exactly
   this — a `set-spacing` override that "outlives every load-config and every SIGUSR1" — but it runs
   only at `:165`, i.e. **on the content-change path only**. An override acquired while the config
   is stable is never reconciled and never reported.

**And the toggle's own state file is a self-report, not an observation.** `:74-80`: *"The state file
is the only record of which half is loaded — kitty exposes no way to read the live
`window_title_bar_min_windows` back."* RAN: state file says `off`; nothing on this box can confirm it.

### How we WOULD detect it — and one channel does exist

There is no general option-getter in kitty 0.48.2. There are two real read-only channels:

**(a) `kitty @ get-colors` reads the RUNNING instance's in-memory table.** RAN, against the live
socket, read-only:
```
$ kitty @ --to unix:/tmp/kitty-73832 get-colors
background     #1e1e24        ← config/kitty.conf:1055  background  #1e1e24   ✓ byte-equal
foreground/color0/…            all present
```
This is the only in-memory config readback found on this box. It supports a **canary**: derive a
colour from the config's own content hash (e.g. `color255 #<first 6 hex of the key>`), then
`get-colors` proves the instance holds *the current file generation*. Read-only, ~30 ms, no relayout.

**(b) `kitty @ ls` per-window `lines`/`columns`** — the observable
`scripts/checks/kitty-title-band-verify.sh:141-146` already uses in its sandbox. RAN on the live
instance: `tab1 [46,46,46,8,8,8,8,8] · tab5 [46,46] · tab6 [47]`. Usable as a differential, not as
an absolute, because rows depend on the OS-window pixel height, which `ls` does not report.

**Honest limit of the canary, stated because it would otherwise read as fuller cover than it is:**
it proves *the instance has loaded the current file*; it cannot prove *no narrower scope beats the
file*. A sticky `-o` on a non-colour option survives a successful reload and the canary stays green.
For overrides the only sound control is **enumerate and forbid**: no `-o` at launch (readable from
argv — RAN, the live kitty's argv is bare, no `-o`), `--ignore-overrides` on every `load-config`
(already enforced and pinned at `tests/kitty-conf-bindings.bats:847-861`), and a record of every
`load-config` this box issues.

---

## 5. Adversarial pass — what I nearly missed

I ran three checks against my own conclusions. Two changed the answer.

### A1 — "the running session" is not in ANY population. Measured.

Every check above concerns daemons and terminals. The brief's actual subject — a Claude Code
session — is covered by nothing. And the exposure is total, not theoretical. RAN:

```
~/.claude/CLAUDE.md mtime       : 2026-09-16 23:35:57
claude processes running         : 6
  started BEFORE those bytes     : 6
  started AFTER                  : 0
```

**Six of six running sessions loaded instruction bytes that are not the bytes on disk**, and no
field, hook, ledger rung or auditor on this box reports it. (mtime > start proves none of them
*can* have loaded today's bytes at `session_start`; it does not prove the content differs — see the
limit below.)

**But the observation primitive already exists and is live.** `hooks/instructions-loaded.sh` is
registered on the `InstructionsLoaded` event and writes one row per memory file a session actually
LOADED. RAN:
```
rows 4236 · distinct sessions 910 · all load_reason=session_start
2026-09-17T04:38:41Z  f37530b1…  session_start  User  /Users/chrisren/.claude/rules/00-mission-board.md
```
It records the **path**, never the **content** (`:100-103` — the printf has no hash field). So it
proves *which file* a session read and says nothing about *which bytes*. Adding one
`git hash-object`/`shasum` field at load time converts it from an inventory into a **checkable
claim**, and it is the cheapest L4 win on the box.

Two named limits: the registered matcher is `session_start` only (RAN: `matcher=session_start`, and
4236/4236 rows carry that reason), so a `compact` reload — the one path that *would* refresh a live
session's instructions — is **unobserved**, and the 6-of-6 figure cannot be refined downward with the
instrument we have. And `hooks/config-mirror-assert.sh:6-7` states the structural half: *"A hook
fires AFTER config is loaded, so it fixes the NEXT session, not the running one."* The verdict for
this class can therefore only ever be a **recycle decision**, never a repair.

### A2 — a strictly better L4 primitive than mtime exists, and it is one command

I assumed mtime-vs-start was the best available. It is not. RAN:

```
$ lsof -p 9749
bash 9749 … 255r REG 1,18 111553 970299526 …/claude-infrastructure/scripts/compressor-sentinel.sh
$ stat -L -f 'ino=%i' ~/.claude/scripts/compressor-sentinel.sh   → ino=970299526     ✓ SAME

$ lsof -p 1094
bash 1094 … 255r REG 1,18 105198 911325840 …/claude-infrastructure/scripts/lead-supervisor.sh
$ stat -L -f 'ino=%i' …/scripts/lead-supervisor.sh               → ino=911325840     ✓ SAME
```

**bash holds fd 255 open on the script it is executing, and it re-reads that fd as it runs.** So
the inode behind fd 255 *is* the running image, definitively — not a proxy for it. `git checkout`
and `git merge` write a temp file and rename, so a replaced file gets a **new inode** and the
running bash's fd 255 keeps pointing at the old one. That makes inode identity a direct
"running-vs-on-disk" test with none of mtime's three failure modes (identical-content rewrite,
reload-after-start noise, changed-before-start blindness).

Limits, stated: it is shell-specific (a python/node daemon reads and closes its source, so nothing
remains open to compare), and an **in-place** edit keeps the inode while changing the bytes — which
git never does, but `sed -i ''` on BSD does not either, so the two must be paired, not swapped:
inode identity ∧ content hash equal to trunk's blob.

### A3 — the residency fail-to-fresh has no test, which makes it a hole rather than a decision

I wanted to be fair to `resident_image_stale`'s fail direction, so I checked whether it is pinned.
`tests/deploy-residency.bats` has 15 cases and covers NO-VERDICT for a missing lib (case 5) and for
a lib predating the probes (case 6) — genuinely careful work. It has **no case where an operand
fails to resolve** (unparseable `lstart`, `stat` failure, `ps` returning nothing for a live pid).
That path returns `1 = NOT stale` (`cc-common.sh:159-161`), increments nothing, and renders inside
`N of N … running current bytes`. So the one arm that fails toward the healthy string is also the
one arm with no coverage. That upgrades FAIL-SAFE FLAG (1) from "a defensible trade" to "an
untested hole". Conviction: **90%.**

### Also checked, and it did NOT change the answer

- `scripts/deploy-link-parity.sh` is a real third auditor (checkout→live links, plus a STRAY leg
  for live real files in no checkout — `bin/cc-mail` sat live and unversioned for 5 days). It is
  still L3: topology, never a process.
- `install.sh:1114-1156` **does** `bootout`+`bootstrap` changed plists on the advance path, so a
  landed *job definition* does reach launchd. And `launchctl print gui/$uid/<label>` reads the
  LOADED arguments back — RAN, it returned compressor-sentinel's full resolved argv. So a
  plist-vs-loaded-job comparison is available read-only and nothing performs it.

---

## 6. The minimum verification that makes "live in the running session" a CHECKED claim

### The structural defect, in one sentence

Every check on this box proves **either** `live == checkout` (parity assert, link parity) **or**
`process == live` (residency) — and **no check composes the two**, while a third fact,
`checkout == trunk`, sits in a *different* tool (`wrap-ledger`'s `LIVE_LAG`) that observes no
process at all. The claim anyone actually wants is the composition:

> `process bytes == trunk bytes`

which is `(process == live) ∧ (live == checkout) ∧ (checkout == trunk)`. Each conjunct has an
owner; the conjunction has none. **That is why tonight's ledger read healthy while five files were
absent: the one conjunct that failed was owned by a tool that was not consulted, and the tool that
rendered the verdict had a denominator that could not express it.**

The minimum fix is therefore not more sensors. It is **one composed verdict per artifact class,
each with a THIRD state**, because for every one of them `0` is the healthy value.

### Per class

| # | Artifact class | Strongest claim today | Minimum check that upgrades it | Cost |
|---|---|---|---|---|
| 1 | **Per-invocation scripts** (`hooks/*.sh`, `bin/cc-*`, `scripts/*.sh`) | exists (`-e`) and its class is deployed | extend the `root SSOT` target-resolution arm (`deploy-parity-assert.sh:918-935`) to **all** symlink classes: `readlink` each live link and require the target to be `$REPO/<rel>` | 523 `readlink`s, ~0.2 s. RAN by hand: 518/523 into the checkout, 5 the documented second-installer class |
| 2 | **Resident bash daemons** | argv-named file not modified since start (mtime) | `lsof -p <pid>` fd **255r** inode `==` `stat -L -f %i` of the on-disk path **AND** `git hash-object <resolved>` `==` `git rev-parse origin/main:<rel>` | 2 processes, one `lsof` each |
| 3 | **Resident non-shell daemons** | same, and weaker (no fd to read) | none exists; make the daemon print its own source hash to its log at startup and compare that | n/a today — all 3 resident jobs are bash |
| 4 | **launchd job definitions** | install.sh re-bootstraps on advance; nothing verifies | `launchctl print gui/$uid/<label>` argv `==` the plist's `ProgramArguments` | 26 labels, read-only. RAN: the readback works |
| 5 | **Claude Code sessions** (CLAUDE.md, `rules/`, skills, agents, settings.json) | **nothing** | add a content hash to `hooks/instructions-loaded.sh`'s row (`:100-103`), then a reader compares each LIVE session's loaded hash against trunk's blob | one `shasum` per loaded file per session (2–4 rows/session) |
| 6 | **kitty** | the FILE's hash equals the hash at the last signal | (a) content-hash canary in a **colour**, read back with `kitty @ get-colors`; (b) ban `-o` at launch + `--ignore-overrides` on every `load-config` (already pinned) + log every load-config issued | one socket read, ~30 ms |
| 7 | **Copy classes** (`~/bin` launchers, `~/.claude/CLAUDE.md`, `statusline.sh`) | content `==` checkout | add the trunk conjunct: content `==` `origin/main:<rel>`, not just the checkout | free — one extra `git show` per file |
| 8 | **Live-layer topology** | per-class counts | already good; keep | — |

### The three rules every one of those must obey

1. **A third state, always.** `0` is the healthy value for every one of these, so an instrument
   failure that renders as `0`/`current`/`unchanged` is unfalsifiable. `wrap-ledger`'s `?` law
   (`:1240-1245`, `:1601-1605`) and `deploy-parity-assert`'s exit 3 (`:96-103`) are the two correct
   models already in the repo; residency's `resident_image_stale` and `cc-kitty-reload`'s
   `no-instances` are the two that are not.
2. **Denominate on what was DELIVERED, never on a ref anything can move.** This is
   `LIVE_ADDS_BASE=advance` generalised: `deploy-last-advance` cannot be moved by a bare
   fast-forward, a worktree pull, or anything but a converge that ran. Every check above should
   take its "as of" from the same file.
3. **The verdict must name an ACTION, and for class 5 the action is a recycle, not a repair.**
   `hooks/config-mirror-assert.sh:6-7` — a hook fires after config load, so it fixes the next
   session. A stale-instructions verdict therefore feeds the existing `♻️ Recycle` disposition,
   which is a rail that already exists.

### If only ONE thing is built

**Class 5, the hash field in `instructions-loaded.sh`.** It is the smallest diff (one field in one
printf), the population it covers is the one the question asks about, the exposure is measured at
**6 of 6 live sessions**, the observer is already registered and already producing 4,236 rows, and
the remedy it points at is a rail that already exists. Every other row above is an improvement to a
check that at least exists.

---

## 7. Conviction

| Claim | Conviction |
|---|---|
| No check on this box composes `process == live` with `live == trunk` | **96%** |
| `deploy-parity-assert` cannot see checkout-vs-trunk lag, by construction | **99%** (RAN: 22/22 `ok` at lag 3) |
| 19 of 22 classes are checked for link EXISTENCE, not link TARGET | **95%** |
| `LIVE_ADDS` is denominated on `deploy-last-advance`, right operand trunk | **99%** (code + its own measured record) |
| A fast-forward creating no symlink drove the lag to 0 while delivering nothing | **99%** (measured in-file, 2026-09-04, 5 named files) |
| Residency is the only L4 probe, and covers 2 processes | **97%** (RAN) |
| `resident_image_stale`'s unresolvable-operand path renders as healthy and is untested | **90%** |
| `cc-kitty-reload`'s `no-instances` latches a failed census as deployed | **88%** |
| `kill -USR1` rc 0 proves delivery, not reload | **93%** |
| SIGUSR1 reload preserves sticky `-o` overrides, so cc-kitty-reload cannot clear that class | **85%** (READ, not measured — measuring it writes to the operator's live kitty) |
| `kitty @ get-colors` is a genuine in-memory readback | **98%** (RAN, byte-equal to `kitty.conf:1055`) |
| bash fd 255 inode is the running image, strictly better than mtime | **94%** (RAN on both daemons) |
| 6 of 6 running sessions predate the current `~/.claude/CLAUDE.md` bytes | **97%** (RAN; upper bound — a `compact` reload is unobserved) |

## 8. Blockers / what I could not settle

- **The sticky-`-o`-survives-SIGUSR1 claim is READ, not RAN.** Confirming it requires a
  `load-config` or a SIGUSR1 against the operator's live kitty, which relayouts every live Claude
  pane. A sandbox instance cannot express the bug — `kitty-pane-title-toggle.sh:88-93` records
  exactly that: *"A fresh instance cannot express this bug; only a long-lived one can."*
- **The 6-of-6 figure is an upper bound.** The `InstructionsLoaded` registration matches
  `session_start` only, so a `compact` reload is invisible; the instrument cannot refine it down.
- **`resident_program` picking the last existing-file token in argv is latent, not live.** All 3
  current plists have clean argv. Whether the next one does is unknowable from here (60%).
- **Not measured:** whether a hook ADDED to `settings.json` after a session started is picked up by
  that session. That is the session-level analogue of the landed-ADD class and would sharpen class
  5's scope; it needs a live A/B I declined to run against the operator's sessions.
