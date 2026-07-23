## AXIS 3 — Actuation Reliability: what makes a session EXIST and ENGAGE

Read-only. Live-fleet verified 2026-07-20 ~08:00 UTC. All claims carry file:line or a live read.

---

## 1. System model as-of-today (delta vs. prior corpus)

**Closed since p01/p02 (verify each historical race — done):**

| Historical race | Status today | Evidence |
|---|---|---|
| G-P1-2 / INC-4 cold-fire "looks fired, never engages" | **CLOSED for non-recycle fires** | `ENGAGE_VERIFY=1` for every real non-recycle fire (`handoff-fire.sh:1313`); `verify_engagement` gates the success line, `exit 1` on miss (`:1948-1960`) |
| ttys018 ZLE char-transposition mis-inject | **CLOSED** | bracketed-paste + echo-verify-before-CR, 4 attempts, destructive Enter gated on proof (`:310-342`) |
| C1 focus-steal | **CLOSED** | autonomous default surface = `bg-tab` (`:1072-1074`); `it2py bgtab` captures/restores/asserts operator focus atomically and self-cleans on a genuine steal (`:1570-1592`); split path asserts via `restore_focus_or_fail` (`:1627-1636`) |
| FM-D empty payload | **CLOSED** | `[ -s ]` (`:1058`) |
| as_tty leaking a non-3 exit under load | **CLOSED** | retry wrapper, always exit 0 (`:209-229`) |
| osascript `write text` for typing | **PARTIALLY retired** — retired for `--tab`/`--window` launch typing; **still the only transport for `/exit`** (`:1008`, `:1850`) |
| G-P2-5 payload-lint dead | **CLOSED** (`payload_lint_gate … enforce`, `:1943`) |
| G-P2-1 completion-push dead | **CLOSED** — 56 records on disk, all `verified` |

**Still open / newly measured:** `--recycle` has **no engagement verification at all** — the watcher confirms only *a claude process on the tty* (`:613-615`), never brief ingestion. The deterministic self-recycle rides exactly that path, so the fleet's most autonomous actuation has a strictly weaker success criterion than its most manual one.

**Live actuation state, measured:**

- `waiting-recycle` production record over the whole IDL: **0 fired, 0 stage2-shadow, 0 stage2-live, 0 escalated**. 4,930 `not-armed`, 176 `below-threshold-no-tell`, 54 `live-team-hold`. The two-stage spine (dc822bc → abecaad → 4c249a9) has fired **zero times**, 24h after go-live.
- The live desk = pane `D08B4FC0` (`cc-roles/desk` ✓), cwd `…/claude-infrastructure` ✓, **`CLAUDE_CONFIG_DIR=$HOME/.claude-quaternary`**, argv shows it is itself a recycled desk ("recycled at 73% context") — so the *model-driven* recycle works; the *deterministic* one has never run.

---

## 2. Frontier rows (ranked)

### F1 — Actuation predicates bind to locally-recomputed identity tuples; there is no canonical identity, and the inertness detector whitelists the failure

**Problem.** Every gate in the stack re-derives "who am I / who is the desk" from a different tuple, computed independently at arm-time and at fire-time. When the tuples disagree the mechanism goes silently inert and reports healthy.

**Evidence (all live).**
- Arm key = `shasum("$CLAUDE_CONFIG_DIR|$PWD")` (`waiting-recycle.sh:112`), state under `$CLAUDE_CONFIG_DIR/state/waiting-recycle` (`:102`).
- Desk runs under `.claude-quaternary` → computes key `cddcfbe2e938785c`. On disk: `arm/brief/live-df1308af96473054` (`$HOME/.claude`) and `…-e181330604ffe33f` (`.claude-tertiary`) only. **`.claude-quaternary/state/waiting-recycle` is empty.**
- `desk-arm-live.sh` — the go-live actuator built *specifically to fix CFG-stranding*, and whose header documents the migration `.claude-tertiary → .claude` — hardcodes `CC_ARM_CFGS:-$HOME/.claude $HOME/.claude-tertiary`: **2 of 5 config roots**. It ran 2026-07-19T11:38Z and reported success. The desk has since migrated to a third root the fix does not cover.
- Net: `live_for()` absent → even when the trigger fires, Stage 2 is **SHADOW forever**. The operator performed the silver-platter go-live and got a green result for a dead mechanism.
- Second, independent identity split on the *same pane*: `cc-registry/D08B4FC0.json` still says `pid 10768` (**dead**), `name tmp-D08B4FC0`, `cwd /private/tmp`, `account claude-secondary` — all stale from a prior generation. So `cc-sessions` **omits the live desk**, while raw-UUID role addressing reaches it fine (56 completion-pushes verified). Two subsystems hold contradictory truth about one pane; `cc-reconcile` (ad37447) did not repair it. `cc-roles/operator` + `orchestrator` → `D5D419C8`, **not an existing iTerm2 pane at all**.
- The designed detector for this exact class explicitly excludes it: `idl-abstain-alarm.sh:15` names *"waiting-recycle (not-armed)"* as a **DORMANT** reason — healthy, never paged. `not-armed` is semantically honest and operationally false; nothing can distinguish "a builder, correctly unarmed" from "the desk, armed under a key it will never compute."

**Why the default tier is insufficient.** Every layer here was individually built, tested (59 bats), landed, activated, and monitored — and the composite is inert. The default tier keeps producing *another* per-observation patch (arm → arm-by-default → desk-arm-live → more config roots) against an enumerated set of observed tuples, while the defect is that identity is *derived* rather than *asserted*. Recognising "stop enumerating tuples, bind to a canonical record" is a re-founding move, not a fix.

**Solution-shape.** This is the empirical case for **C-DSH-1**: one write-before-act, session-owned attestation record — `{pane_uuid, session_id, pid, cfg_dir, cwd, role, state, lifecycle}` — written by SessionStart and refreshed by the poll loop, with every consumer (arm lookup, role resolution, registry, reaper, dispatch) reading *that* rather than recomputing. Promote via `/frontier-campaign`; the arm key becomes a lookup, not a hash. Add the missing detector class: **"a mechanism that has never once fired since arming"** — orthogonal to abstain-reason classification, and the only signal that would have caught this.

**Confidence: HIGH** (every link disk-verified).

---

### F2 — The binary the entire actuation stack contracts with is unpinned, auto-updating, and misnamed

**Problem.** ~15 load-bearing behavioral assumptions about the `claude` binary are encoded as prose, validated once, and never re-asserted — against a binary that silently advances.

**Evidence.** `handoff-fire.sh:144` pins the probe to `$HOME/.claude-183/node_modules/.bin/claude`. That binary **reports `2.1.215`**. `~/.claude-versions/current → 2.1.114`. 31 live fleet processes run `.claude-183/…`. So the version-pin machinery (MANIFEST skip-list, `pre-session-validate.sh` rollback) governs a path the launchers don't exec, and the directory *name* asserts a version 32 patches behind its contents. `DISABLE_AUTOUPDATER=1` appears exactly once, in `probe_account` (`:1214`).

The implicit-contract surface (generalising C-DSH-2 beyond `/exit`):

| Contract | Where relied on | Validated at |
|---|---|---|
| `/exit` interrupts a turn, exits in seconds | `:988-990`, `:1832-1839` | 2026-07-03 E2E |
| plain text steers into a running turn at the next tool-result boundary | `:1099-1108` | catnav incident |
| Ink binds Enter to `\r`, ignores `\n` | `cc-notify:17-18`, `:551` | 2026-07-03 |
| composer prompt glyph is `❯` (U+276F) | `cc-notify:165` — strand detection | undated |
| `/goal` hard-caps at 4000 chars | `check_goal_length:465-482` | doc-derived, receiver never re-verified |
| `claude "<argv prompt>"` auto-submits | every `CMD` composition | INC-4 showed it can fail |
| trust gated by `.claude.json projects[dir].hasTrustDialogAccepted` | `pre_trust:1187-1205` | — |
| turn-interrupt SIGKILLs the tool's whole process group | `detach()` rationale `:260-268` | 2026-07-13 ×2 |
| PostToolUse `decision:block` + `additionalContext` reaches the model | `waiting-recycle.sh:69` | **"confirmed @ 2.1.183"** |
| transcript JSONL shape, `projects/` layout | `engagement_seen`, rot-tell reader | — |
| bracketed paste accepted literally by both zsh ZLE and Ink | `:310-342`, `:349-354` | 2026-07-19 |

**Why the default tier is insufficient.** The default tier reasons *forward* from a documented behavior; it cannot know that behavior silently changed. Each drift surfaces as an unrelated incident (a mis-inject, a stranded /exit, a task-less worker) and gets patched locally — the 10-fix stratum in `handoff-fire.sh` is largely a fossil record of undetected contract drift.

**Solution-shape.** C-DSH-2 is necessary but under-scoped. What's needed: (a) a **contract fixture suite** covering all rows above, executed against a *disposable* pane on every binary change; (b) a real pin — the launcher execs a version-locked path with the auto-updater disabled, and `record-version.sh` gates promotion on the fixture suite; (c) rename the dir to its true version or stop encoding versions in paths. Cheap, high-yield, and it converts an unknown-unknown generator into a known gate.

**Confidence: HIGH** on the drift; **MEDIUM** on which specific contracts have already broken (undetermined — see §4).

---

### F3 — The destructive keystroke is the least-verified primitive; the substrate offers no readable state machine

**Problem.** Verification effort is inverted with respect to blast radius.

- **Launch command** (recoverable if it fails): Ctrl-U scrub → bracketed paste → screen re-read → `grep -qF` → CR only on proof → 4 attempts → fail loud (`:312-342`).
- **`/exit`** (irreversible; kills a live turn): bare `osascript … write text "/exit"` (`as_write:189-207`), **no echo-verify, no state check**, 3 attempts on *osascript* success — which proves only that AppleScript ran, never that the composer received a well-formed slash command. The acknowledged strand rate for the submitting Enter is **~1-in-6** (`:573`, `cc-notify:24`).
- Failure handling is **unconditional force-close**: `__selfclose` polls ≤180s, and then `"$HOME/.claude/bin/it2" session close -f -s "$SID"` runs *regardless* of whether CC ever agreed to exit (`:546-555`). A mangled or swallowed `/exit` therefore ends as a force-kill of a live session mid-turn. In `--recycle` the same failure is benign-but-silent: the watcher gives up at 600s (`:588-590`) and no recycle happens.

**Why this is the substrate question (sub-question b).** You *can* echo-verify a shell input line because a shell exposes its state as text on a screen. You *cannot* verify a TUI composer's state: whether it is idle, mid-turn, at a permission modal, or at a resume prompt is not machine-readable. The entire stack works around this with heuristics — `ps` on the tty, a `❯` glyph grep, blind CR nudges at 60/150/300s, timeouts. **Keystroke-into-a-TUI is a write-only channel with no acknowledgement**, and every reliability fix so far has been an attempt to synthesise an ack from screen scraping.

**What is available without the Agent SDK / at-cost API:**

| Substrate | Machine-readable ack | Operator-visible | Sustains a long session | In-repo precedent |
|---|---|---|---|---|
| it2 keystroke injection (today) | ✗ (scraped) | ✓ native panes | ✓ | the whole stack |
| `claude -p` headless | ✓ (exit code + JSON) | ✗ | ✗ one-shot | `probe_account:1214`; `lr-reset-poller.sh:20` rejects it explicitly for this reason |
| **detached tmux PTY** | **✓ (`has-session`, `capture-pane`, `wait-for`, exit status)** | ✗ while detached | ✓ | **`lr-reset-poller.sh:89-91` — already shipping** |
| **tmux + iTerm2 `-CC` control mode** | **✓ same tmux control surface** | **✓ real iTerm2 tabs/panes** | ✓ | none |

The decisive point: **`spawn_tmux` already proves a keystroke-free FIRE primitive exists in this codebase** — it launches the launcher as `tmux new-session -d … "/bin/bash $launcher"`, so the prompt rides argv/file and *no keystroke is ever injected*. Its only deficit is the operator's standing visible-pane requirement (memory: `feedback-dedicated-split-pane-sessions-for-parallel-work`). iTerm2's native tmux integration (`tmux -CC`) dissolves exactly that trade-off: tmux windows render as **real iTerm2 tabs/panes** while remaining addressable by tmux's control protocol. That would give spawn-with-exit-status, `has-session` liveness, `capture-pane` reads, and `send-keys` with a real ack — and would retire `as_write`, the CR-nudge ladder, the `❯` grep, and much of `it2py`.

**What would be LOST:** ⌘D split-of-the-firing-pane geometry (tmux owns the layout inside a `-CC` window); the Claude-Teammate profile injection (`it2-wrapper:26-29`); per-pane iTerm2 profile inheritance; and one new failure domain (a dead tmux server kills every session in it — worse than today's independent panes). Migration is not all-or-nothing: **fire and recycle** are the two primitives worth re-founding; `cc-notify` (interrupt into a *running* session) still needs a keystroke-class channel regardless of substrate.

**Confidence: HIGH** that the substrate is the root constraint; **MEDIUM** on `tmux -CC` viability (not empirically tested here — see §4).

---

### F4 — Engagement verification's stated timeout is off by ~4× in wall-clock, and degrades with transcript-corpus growth

**Problem.** `verify_engagement` (`:384-402`) increments a logical counter by `interval` while each probe performs a **full-corpus grep**.

**Measured.** `find "$pdir" -name '*.jsonl' -exec grep -lF -- "$marker" {} +` over `.claude-tertiary/projects` — 2,410 files / 973 MB — took **9.6 s wall, 7.45 s user CPU**. `.claude/projects` (the `next`/`claude-next` target) is 2,438 files / **1.1 GB**. So each loop iteration costs ~12.6 s wall while `t` advances 3 → the documented **120 s** engagement window is **≈8.4 min**, and the +60 s retry adds ≈4.2 min: **≈12.6 min of blocking, ~100%-of-a-core wall time per fire**.

`cc-dispatch:221` fires **serially** inside the placement loop, up to `MAX_SPAWN`. A full wave therefore blocks on the order of **~100 minutes** and saturates a core with repeated 1.1 GB scans, on a launchd-driven job (`com.claude.dispatcher` is loaded). This plausibly explains a class of "the fire hung" observations without any keystroke pathology at all.

**Why it is invisible.** `fire-engagement.bats:21` constructs a temp `$HOME` whose `projects/` holds 1-2 files. The test's hermetic isolation is precisely what hides the production cost — the same shape as p01's finding that `boundary-hook-e2e.sh:32` wrote the `gate-green` fixture the real flow never wrote. **Green tests are structurally incapable of seeing this class**, and it is the third instance of that pattern in this stack.

**Why not merely routine.** The naive fixes are each wrong: shrinking the timeout re-opens INC-4; disabling the verify re-opens the cold-fire race; parallelising the wave multiplies the scans. The real answer is a **positive engagement signal at birth** — the fired session announces its own marker (SessionStart hook writes `engaged/<marker>`), turning an O(corpus) search into an O(1) file-existence check. That is C-DSH-1's `lifecycle: engaged` field again, which is why F1 and F4 collapse into one campaign.

**Confidence: HIGH** (measured).

---

### F5 — "Attest, then fire, then discard the actuator's verdict" — a documented anti-pattern reproduced in new code one day later

**Evidence.**
- `waiting-recycle.sh:456-461`: IDL records `fired: stage2-live` **before** `"$HANDOFF_FIRE" --recycle … >/dev/null 2>&1 || true`. Every failure mode handoff-fire is engineered to report loudly (`watcher heartbeat never appeared`, `could not type /exit — watcher disarmed`, `no routable account`) is discarded, and the audit trail asserts a fire that may not have happened.
- The latch `: > "$firedf"` is burned first (`:441`), so a transient iTerm2 hiccup permanently disables Stage 2 for that SID.
- The resulting escalation then **misdiagnoses itself**: `:483` reports *"a SHADOW would-fire is latched but the exec is not armed --live"* — false when a LIVE fire simply failed, and it instructs the operator to perform an action already performed.
- `cc-dispatch:221` has the identical shape. This was explicitly called out — *"Un-swallow: `cc-dispatch:219` (`>/dev/null 2>&1`) must capture the fire's stderr to the IDL"* (`desk-anti-hitl-2026-07-19.md` Part C rec 2) — and the pattern was then reproduced verbatim in the new Stage-2 path.

**Why frontier-adjacent.** The individual fixes are trivial (route stderr to the IDL, latch after success). What is not trivial: a documented defect class propagated into new safety-critical code within 24 hours, because nothing structurally forbids it. The generator is **attestation-before-effect**; the counter is a repo-wide invariant — *no IDL `fired` record may be written before the actuator's exit status is known* — enforced by a lint over IDL emit sites, in the spirit of `payload-lint`/`reaper-horizon-lint`.

**Confidence: HIGH.**

---

## 3. NOT frontier — routing

| Item | file:line | Route |
|---|---|---|
| `CC_ARM_CFGS` covers 2 of 5 config roots | `desk-arm-live.sh:78` | cc-backlog, **P0** — one-line fix un-blocks deterministic recycle today |
| Un-swallow fire stderr into the IDL; latch after success | `waiting-recycle.sh:441,461`; `cc-dispatch:221` | cc-backlog, P1 |
| Wedge escalation misreports a failed LIVE fire as "not armed --live" | `waiting-recycle.sh:483` | cc-backlog, P1 |
| `cc-roles/{operator,orchestrator}` → non-existent pane; `desk` registry row stale (dead pid, wrong cwd/account) | live | T-P2-2 role self-heal (still open); `cc-reconcile` backfill missed this row |
| `verify_engagement` re-sends **into the same pane** — contradicts "never re-send into the same pane" | `handoff-fire.sh:393-395` vs `desk-anti-hitl` Part C rec 3 | cc-backlog, P2 (mitigated by bracketed paste) |
| `__recycle` guarded-retype TOCTOU: `! cc_alive` then type; claude can start in the gap → Ctrl-U + paste + CR into the composer | `:608-610` | cc-backlog, P2 |
| `it2-wrapper` doubles as a config file regex-parsed by another script; a reformat silently degrades splits to the Teammate profile and `it2py` to bare `python3` | `handoff-fire.sh:1454,1463` | P2 — verified benign today (both paths resolve; bare `python3` *does* import `iterm2`) |
| `cc-notify` injects a raw char-stream (no bracketed paste) — a multi-line message may submit in fragments | `cc-notify:133-134` | P2 |
| `idl.jsonl` 40 MB (was 114 MB) | — | **improved** by b59f1cf; no action |
| `com.claude.{dispatcher,discovery}`, `autonomy-sweep` now **loaded** (last exit 0) | `launchctl list` | **updates memory** `desk-autonomy-dormancy-staged-not-loaded` — the spine is no longer inert-by-staging |

---

## 4. Could not determine

1. **Whether `cc-notify` injection into a session sitting at a permission/AskUserQuestion modal actuates the highlighted default.** `cc-notify` has *no* modal guard; on a modal there is no `❯`, so `composer_stranded` returns 2 → **"UNVERIFIED" → exit 0, reported delivered** (`:178-181`). The trailing `\r` would confirm whatever option is highlighted. If real, the desk already possesses the keystroke-approval capability `desk-anti-hitl` Part B rules must stay at the empty set. Requires a controlled live test — **out of scope for a read-only brief; recommend a dedicated fixture pane.**
2. **Which of the ~15 implicit binary contracts have already drifted** between 2.1.183 and the running 2.1.215. Not testable read-only; this is C-DSH-2's payload.
3. **`tmux -CC` viability** (Claude's Ink TUI inside iTerm2 control-mode; profile/scrollback behavior; whether `send-keys` reaches Ink identically). Untested.
4. **Why the desk's Stage-1 advisory never fired despite reaching 73%** — zero `waiting-recycle` `fired` records ever, yet the desk demonstrably recycled at 73%. Candidates: the recycle predates arm-by-default (abecaad, 2026-07-19), or an S4/S5 hold suppressed it. Notably **`inbox-active-hold` has 0 records** despite a 72 KB desk mailbox — either S4 never trips or it is unreachable behind an earlier abstain. Worth one targeted trace.
5. **`/exit` strand rate on 2.1.215** — the ~1-in-6 figure is a 2026-07-13 measurement against a much older binary.

---

**Bottom line for synthesis.** The keystroke-corruption era of this stack is genuinely over — bracketed paste, echo-verify, focus assertion, and engagement verification closed the races p01 flagged. What replaced them is subtler and worse-behaved: **the actuation layer's failures are now all in the attestation layer**, not the transport. The fleet's deterministic recycle is 100% inert while every gate reports green; the engagement verifier's own timeout is a 4× wall-clock fiction that only grows; the audit trail records fires that never happened; and the binary these contracts are written against changes underneath them without a version anyone can name. F1 and F4 collapse into a single campaign (C-DSH-1's attestation record dissolves both); F2 is a cheap, bounded, high-yield gate (C-DSH-2, scoped up); F3 is the standing structural question, and the codebase already contains its own existence proof in `lr-reset-poller.sh:89`.
