# The assignee self-close chain in kitty — convicted end to end

**2026-08-04.** Produced by a 14-agent wave (10 disjoint evidence axes + 3 adversarial lenses +
synthesis; 2.39M tokens, 0 errors) plus four lead-side experiments. This is the FULL design; the
plan doc `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md` carries the orchestration and the
corrections that supersede parts of it.

## Lead-side corrections to the synthesis below — read these FIRST

**C1 · §7's "single highest-value unrun experiment" is REFUTED by measurement, not deferred.**
The synthesis proposes spawning an assignee with `AgentInput.isolation:"worktree"` to give each
member its own cwd, and bounds every §3 change as "a downstream workaround whose necessity is
unproven until this is measured". It was measured. On 2.1.220 the spawn branch is
`if (teamContext && name && !fork && !isolation && !cwd)` — passing `isolation` ALONGSIDE `name`
**silently demotes the spawn to an in-process subagent**. Observed 2026-08-04 01:18 for a probe
named `wtprobe`: no `--agent-id` child process (confirmed from INSIDE the agent too — its own
process line carries no `--agent-id` flag at all), kitty window count unchanged (21 before, 21
after), no membership in the session's `config.json`, no error — and an in-process subagent
transcript at `subagents/agent-<id>.jsonl`, which is the demotion tell.
⇒ **There is no spawn-side remedy on this runtime. Every §3 change is NECESSARY, not optional.**

⚠ **C1 correction — a worktree IS created, and on this box it landed in the WRONG REPOSITORY.**
An earlier draft of this line said "no worktree created"; that was inferred from
`git -C claude-infrastructure worktree list` showing nothing new, and the inference was wrong.
The probe reported `pwd=/Users/chrisren/Development/.worktrees/wt-pool-2`, branch
`agent-a9cac33d5c961c805`, and `.git` a FILE reading
`gitdir: /Users/chrisren/Development/reso-management-app/.git/worktrees/wt-pool-2`. Verified:
claude-infrastructure's worktree list contains it 0 times; reso-management-app's lists it.
**So an agent spawned with `isolation:"worktree"` from a claude-infrastructure session was placed
in a reso-management-app worktree.** This probe was read-only; a code-writing agent would have
written into the wrong repo. Filed separately — it is not part of the self-close fix, but it is a
data-integrity finding that this investigation surfaced and must not absorb silently.

> **RESOLVED 2026-08-08 — backlog 4afd0515c83a, landed 72abcf14.** The placement was ours, not the
> vendor's: `isolation:"worktree"` fires the WorktreeCreate hook, and `hooks/worktree-setup.sh` then
> fell back to the machine-GLOBAL `$HOME/.reso/bin/worktree-pool.sh` for any repo shipping no
> allocator of its own, which handed back one of reso's shared `wt-pool-N` slots switched to our
> branch. `worktree-lifecycle.log` holds both events — `wt-pool-2` at 2026-08-04 01:18 (this probe)
> and `wt-pool-9` at 2026-08-05 01:16. efecf749 removed that fallback and reso's 99753cf31 refuses a
> foreign caller; 72abcf14 adds the assertion neither of them makes — every rung's returned path is
> checked against the expected repo's common git dir before it is printed, so the class is closed
> rather than two of its spellings. Re-measured live on 2.1.220: a fresh `isolation:"worktree"` probe
> landed in `wt-agent-a5c50396d1a00261c` with its gitdir in claude-infrastructure.

**C2 · The hook prescribes the thing C1 just disproved, and so does the backlog.**
`hooks/teammate-auto-shutdown.sh:837` SURFACEs *"Fix at spawn (give the member its own cwd)"* — 231
times all-time — and backlog #140 repeats it. Following that instruction produces a NON-teammate
with no pane, silently. The message must be corrected in the same PR, or it keeps directing
maintainers into a trap. (Class: `prescribed-remedy-worse-than-the-bug`.)

**C3 · A pane cannot close by the member exiting — our own runner forbids it.**
`bin/cc-pane-runner:115` calls `_fallback ""`, which `exec`s an interactive login shell when the
agent command returns. Probe (window 417, 2026-08-04 00:1x): the window survived its command and
dropped to a `➜ ~` prompt. So even a PERFECT vendor shutdown (`approve:true` ⇒ `claude.exe` exits)
leaves an open kitty window. **External `close-window` is mandatory, not a fallback.** Measured:
`kitty @ close-window --match id:N` returns rc=0 with no confirmation prompt.

**C4 · The "third close path" is vendor teardown while the lead is ALIVE — not lead-exit.**
Team `session-57342265`: all 6 members closed and were removed from `config.json`, with ZERO
`teammate-lifecycle.log` lines, while the lead (pid 47878) stayed running in the same worktree.
So the vendor closes panes on explicit lead teardown. It is not a substitute for the idle-reap
backstop: team `session-cf2eaa02`'s 12 assignees have a live lead, 10 are `isActive:false`, and
nothing has reaped them for over an hour. **Consequence for the alarm: the first `departed` it
observes may be the vendor's, not ours — attribute before claiming the fix worked.**

---

# CONVICTED ROOT CAUSE — measured live at 2026-08-04 01:07–01:08

**The per-member attribution verdict the hook already computes is thrown away before the gate that actually blocks, and that gate re-asks the same question against the wrong tree.** One untracked file written by the *lead* is currently blocking the self-close of twelve assignees.

Live reproduction, running now (better than the dead one in the brief — capture it before it drains):

- Team `session-cf2eaa02`, **13 members**, config `/Users/chrisren/.claude-secondary/teams/session-cf2eaa02/config.json`; 12 assignees carry **integer** `tmuxPaneId` 438–449 and all 13 record the same `cwd=/Users/chrisren/Development/.worktrees/wt-cc-001759-77337`. `it2 session list` → `359 409 410 438 439 440 441 442 443 444 445 446 447 448 449 206 207 208 209 210 211`; `ps … --agent-name` → 12 matching processes.
- Shared tree `git status --porcelain` → **exactly one line**: `?? docs/research/IMAGE_FIDELITY_BANDING_2026-08-04.md` (+8 gitignored).
- Hook attribution, last hour: **10/10** `↳ <m>: shared cwd is dirty, but NOTHING this member wrote is — a sibling's dirt is not its own (per-file attribution)` ⇒ `TREE_DIRTY=false` at `hooks/teammate-auto-shutdown.sh:723` ⇒ rule 3 at `:741` correctly **skipped**.
- reap-guard newest records: `colour DEFER dirty-tree`, `next-config DEFER dirty-tree`, `pipeline-arch DEFER dirty-tree` (`enc-depth DEFER grace-held`, legitimately young).
- Hook defers, last hour: **14/14, single reason** — `defer <m> (n/3): reap-guard DEFER on a SHARED cwd (…) — gates evaluated the wrong tree`.

`scripts/reap-guard.sh:118` is `if [ -d "$wt" ] && [ -n "$(git -C "$wt" status --porcelain …)" ]` — a whole-tree read that has no idea the hook just exonerated this member. This is the gate-chain axis's prediction ("reap-guard asks the identical question one gate later") now confirmed with a positive control the earlier waves never had: **attribution CLEARS and the close still refuses.**

This also settles two disputed framings: S5's refutation stands (the tree is *not* permanently dirty by design — it is transiently dirty from a sibling, and the wait has no deadline), and the wrong-target red team's "current population is 0 integer pane ids" is **stale — it is 12 right now.**

---

## 1. THE CHAIN

Every link from "assignee finishes" to "kitty window is gone". Line numbers are HEAD `9f0b3602`.

| # | Link | Today | Evidence |
|---|---|---|---|
| L1 | Turn ends ⇒ `TeammateIdle` emitted | **TRUE** | Sole emitter `Ron` @237762975 in `claude.exe`, called after the Stop-hook chain, gated on `o_()` (process-local agentId+teamName). Live: 14 hook decisions in the last hour. Supply is TURN-driven, not timer-driven — no heartbeat exists. |
| L2 | Member → worktree resolution | **TRUE (as SHARED)** | `:657-673` team-config cwd leg; `:669` logs `is SHARED by 13 members — gating on it, removal refused`. `WORKTREE_OWNED=false`. |
| L3 | Whole-tree dirty read `:687-692` | **TRUE** (reads dirty) | 1 untracked file. |
| L4 | F1 per-member attribution `:713-730` (`session_dirty_mine`, rc 0/1/2) | **TRUE — works** | 10/10 clears tonight; rc contract `hooks/lib/session-writes.sh:22-26`. |
| L5 | Rule 3 dirty-defer `:741` | **TRUE — correctly skipped** | Zero `dirty tree` defers in the last hour. |
| L6 | Tool-in-flight hold `:763` | **TRUE** | Unbounded, transcript-read, independent of `$WORKTREE`. |
| **L7** | reap-guard `decide` `:809` | **BROKEN #1** | `reap-guard.sh:118` re-reads the WHOLE tree → `DEFER dirty-tree`. The attribution verdict is never passed. Also `:123` `has_products` first clause `git log -1 --format=%ct > spawn` (`:70-71`) is **vacuously true** on a shared tree (the lead commits), so R-b never asks its per-member question either. |
| **L8** | Shared-cwd arm `:828-841` | **BROKEN #2** | Treats *any* non-zero from reap-guard as a safety hold: bounded defer `:831-835`, then `⚑ SURFACE` `:837` + `exit 0`. Never closes. 231 SURFACE lines all-time, 80 distinct (team,member) pairs, **0 ever closed**. |
| **L9** | Operator-adoption / R-d `reap-guard.sh:137-158` + belt `:956-1048` | **BROKEN #3 (latent — becomes the blocker once #1/#2 land)** | Prior team's newest records were `reason_kind=operator-adopted`, driven by the LEAD's own `<teammate-message teammate_id="team-lead">{"type":"shutdown_request"…}` user-role record. `hooks/lib/context-econ.sh:330` `CC_CE_AUTO_RX` excludes `^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|…` — **not** `^<teammate-message`. Every shutdown_request re-arms a 6-hour hold. |
| L10 | Checkpoint `:892` | TRUE (unreached today) | Temp-index plumbing (`teammate-checkpoint.sh:188-199`), never touches `.git/index`. ⚠ Its `✓ final checkpoint written` is an **rc claim, not a ref** (`:140-143`, `:201-204` both exit 0 writing nothing). |
| L11 | PANEID from `config.json .tmuxPaneId` `:925-939` | **TRUE (data present, identity ABSENT)** | 12 integer ids live. Both identity-gated fallbacks are dead under kitty: `_pane_from_env` `:293` requires a UUID regex and the live value is `ITERM_SESSION_ID=w0t0p0:442`; `_pane_from_tty` `:311` needs a running iTerm2 (`pgrep -x iTerm2` empty). |
| L12 | `pin_term_verdict` `:1091-1106` before the detached close `:1112` | **TRUE** | Exports `CC_TERM=kitty` foreground; `bin/cc-in-kitty:67-68` honours it verbatim ahead of the ancestry walk. |
| **L13** | `close_and_log :211` → `close_pane :136-144` → `it2` → `it2-kitty:477` | **TRUE but NEVER EXERCISED, and UNVERIFIED IN IDENTITY** | Probe-verified rc=0 + window gone. But **zero** close paths have reached it in the 1,494 kitty-era log lines; and `bin/it2-kitty:209 valid_id` is a digits-only *shape* check — a positive control closed a non-claude window. The comment licensing that, `:132-134` ("iTerm2 session UUIDs are never recycled, so a stale id can only no-op"), is **false**: kitty window ids are a per-process counter restarting at 1. |
| L14 | `pane_present` verify `:182-189`, three-state | TRUE | Correctly written. |
| L15 | `git worktree remove --force` `:1137` | **TRUE — correctly refused** | Guarded by `$WORKTREE_OWNED` `:1134`; else-arm `:1141` `~ worktree kept (shared, not owned by …)`, executed 3× historically. **This is the only destructive verb in the entire close path.** |

**Fix order is forced, not preferential:**

1. **L7 + L8 in one commit.** Separately each is a no-op: fixing L7 alone leaves L8 converting the next refusal into the same SURFACE; fixing L8 alone opens an ungated close. Variant-A measurement already proved the half-fix: dirty-half only → `ok 22` still green, `it2-calls.log` still empty.
2. **L13 identity pin, same PR.** The fix is what first arms the actuator, and the exposed population is 12 today. Shipping 1+2 without it is shipping an unverified close against a per-process integer.
3. **L9** — will be the sole remaining blocker after 1+2. Ship it in the same PR or accept a second zero-move day.
4. Backstop depth (`cc-reconcile` `no-sid`, `cc-classify` agent-blindness, `cc-reaper:639`, unloaded `team-orphan-reaper`) — **second PR**, gated on the alarm from §5 existing first.

---

## 2. THE POLICY

**A pane close and a worktree removal are two different acts with two different gate sets, and the current code conflates them.** New policy: *the removal* stays gated on whole-tree cleanliness and ownership exactly as today (`:1134`, unchanged — it is the only destructive verb and it is already refused on a shared tree). *The pane close* is gated on five things and nothing else: **(a) birth-grace** — a member younger than the grace window is not finished (self-resolving, unbounded defer); **(b) tool-in-flight** — a running tool is positive evidence of life, read from the member's own transcript (self-resolving, unbounded, never charged to `MAX_DEFERS`); **(c) own-footprint dirt** — this member's *own* written files are uncommitted, per `session_dirty_mine`, with `rc 2` (cannot-tell) counting as dirty (fail-closed, `MEMORY.md lookup-miss-is-not-absence`); **(d) operator adoption** — a *human* typed into this pane after its spawn brief, where a `<teammate-message>` from the lead is explicitly **not** a human; **(e) target identity** — the recorded pane id resolves, in the *current* terminal generation, to a window whose foreground process carries this member's `--agent-name`. Every other tree-cleanliness question is **deleted on a shared cwd**, because on a shared cwd it can only ever answer about the lead's checkout: a sibling's untracked file is not this member's work, and the whole-tree commit clause of `has_products` is satisfied by the lead's commits regardless of what the member did — a gate whose answer is structurally predetermined carries zero bits and is not protecting anything (it is protecting `:1137`, which `:1134` has already refused). Each surviving gate protects a real thing: (a) and (b) prevent killing a member that is still working; (c) prevents stranding *its own* uncommitted edits (and the pre-close checkpoint at `:892` covers it besides); (d) prevents the 2026-07-24 close-a-live-human-conversation incident class; (e) prevents closing an unrelated window after a kitty restart reissues the id. **The residual this policy knowingly accepts**: a read-only member holding an unsent in-context deliverable is closed. That is bounded — its output channel is the durable mail store (`~/.claude/mailbox`, 1,960 files; the close path has zero references to it) and the transcript flushes on SIGHUP (measured 1.373 s, `last-prompt` resume pointer appended during shutdown) — so the deliverable is recoverable by `--resume`, and a member that never sent it was already failing its contract.

---

## 3. THE DIFF PLAN

### `scripts/reap-guard.sh` — make the tree legs shared-aware (the load-bearing change)

- **`cmd_decide` arg parser `:91-100`** — add `--tree-scope owned|shared` (default `owned`) and `--tree-verdict clean|dirty-mine|unknown` (default `unknown`). Reject unknown values through the existing `die` at `:98`. ⚠ `die` exits **2** and the hook's `if ! "$REAP_GUARD" decide` (`:809`) treats *every* non-zero as DEFER — so any new outcome must be an **explicit** code the hook reads, never a bare non-zero (`MEMORY.md new-enum-member-falls-into-fail-closed-default`).
- **Dirty-tree leg `:118-121`** — branch on scope. `owned` ⇒ byte-identical to today. `shared` ⇒ branch on `--tree-verdict`: `dirty-mine` ⇒ `emit_record … DEFER dirty-tree-mine` + `return 10`; `unknown` ⇒ `emit_record … DEFER dirty-tree-unattributable` + `return 10` (fail-closed); `clean` ⇒ **skip the leg entirely**.
- **`has_products` `:68-75` / R-b `:123-126`** — on `shared`, drop the whole-tree clause `:70-71` (vacuous: last commit `1785830099` > lead `joinedAt` `1785823568` — passes for every member regardless) and keep only the per-member ref clause `:72-73`. Then, because a read-only member has no ref *by construction* (`teammate-checkpoint.sh:201-204` writes nothing when the tree matches HEAD), on `shared` a per-member-ref miss must **not** DEFER — emit `REAP shared-no-refs` with the reason string naming the accepted residual from §2. Do **not** skip `:123` as a block; the per-member clause is the one real signal S2 identified.
- **`--selftest` `:185-243`** — add four arms (shared+clean⇒REAP, shared+dirty-mine⇒DEFER, shared+unknown⇒DEFER, shared+no-refs⇒REAP). This moves the emitted `ok` count from 8 → 12.
- **Unchanged and why**: R-a birth-grace `:109-112` (self-resolving, correct); busy-marker `:114-117` (harmless — note it has **zero production writers**: the only `touch` of that path in the repo is `tests/worktree-gc.bats:157,:427,:713`, and the two on-disk instances are 15 days old, so do **not** count it as depth); R-d `:137-158` structure (only its *predicate* changes, below); `emit_record` `:55-63`.

### `hooks/teammate-auto-shutdown.sh`

- **`:809`** — pass the verdict the hook already has: `--tree-scope "$($WORKTREE_OWNED && echo owned || echo shared)"` and `--tree-verdict <clean|dirty-mine|unknown>` derived from the `_sw_rc` at `:721`. **This requires hoisting `_sw_rc` out of the `if $TREE_DIRTY && ! $WORKTREE_OWNED` block at `:713`** — today it is only computed when the whole tree is dirty; a clean shared tree must report `clean`, not `unknown`, or the fix fails closed on the easy case.
- **`:828-841` (shared-cwd arm)** — this must no longer swallow *every* non-zero. Split on reap-guard's reason: a **WHO/WHEN** refusal (grace-held, busy-marker, operator-adopted, adoption-unresolvable, adoption-unreadable) keeps today's behaviour — defer, and SURFACE at cap. A **WHAT-on-the-wrong-tree** refusal can no longer occur, because reap-guard no longer produces one on `shared`. Read the reason from the record reap-guard just wrote (`$CC_REAP_RECORDS_DIR`, `reason_kind`) or — preferred, and the reason the arg-parser note above matters — from a distinct exit code. Keep `_page_desk_damped` `:838`.
- **`:130-134` comment + `close_pane :136-144`** — delete the false premise, and pass the identity expectation through: `it2 session close -f -s "$pane" --expect-cmdline-match "--agent-name $MEMBER_NAME" --expect-generation "$KITTY_PID"`. The tmux branch `:139-140` is unchanged.
- **`:892-894`** — stop setting `CHECKPOINT_OK` from an exit code. Assert on `git -C "$WORKTREE" for-each-ref refs/wip/$TEAMMATE_NAME/LAST` and log `✓ final checkpoint written (ref)` vs `~ nothing to checkpoint (tree matches HEAD)`. Two distinct true statements instead of one that is sometimes false.
- **Unchanged and why**: `:676-680` busy marker (inert, harmless, and removing it is a separate argument); `:741-750` rule 3 (correct — it fires only on own-footprint dirt, and it checkpoints); `:763-767` tool-in-flight (correct, unbounded); `:863-881` WORKTREE-unresolved fail-closed (a genuinely ungated close must stay impossible); `:1134-1141` removal guard (already correct — this is the whole reason the close is safe); `:1143` backgrounding (the 5 s settings.json timeout is **not** the constraint).

### `hooks/lib/context-econ.sh` + `hooks/lib/cc-interactive.sh` — the WHO predicate

- **`context-econ.sh:330`** `CC_CE_AUTO_RX` — add `^<teammate-message`. **`cc-interactive.sh:78`** `CC_CLASSIFY_AUTO_RX` — the same token, **in the same commit**, or `tests/interactive-parity.bats:118-122`'s `ci_ ⇒ ce_` implication goes red. Rationale: a lead's `shutdown_request` arriving as a user-role record is the *system asking the member to leave*, not a human adopting it — today it re-arms a 6-hour hold against the very close it requests.

### `bin/it2-kitty` — the identity pin (chokepoint), **not** `bin/it2-wrapper`

- **`close` arm `:476-477`** — before `kt close-window --match "id:$SESSION"`, when either new flag is supplied, make ONE `kt ls --match "id:$SESSION"` call (measured 0.036 s; it returns `env.KITTY_PID` **and** every foreground cmdline in the same payload) and require: generation matches, cmdline substring present, exactly one window. **Tri-state**: unreadable / zero windows ⇒ refuse with a new exit code, never close — mirroring `pane_present`'s three-state discipline. **Absent flags ⇒ today's behaviour**, so `handoff-fire` self-close, `cc-pane`, and operator closes are untouched (the red team's "a mispinned check turns a safety pin into a self-close outage" is answered by making the pin caller-supplied).
- **`bin/it2-wrapper:90` — DO NOT EDIT.** It is deployed by **copy** (`install.sh:527`, `scripts/kitty-setup.sh:160-162`) and `scripts/deploy-link-parity.sh:181` globs only `"$REPO"/bin/cc-*`, so an edit there lands, reports `✓ every landed file is live`, and is **dead**. The daemon-caller gap it would fix (launchd never sets `KITTY_WINDOW_ID`) is real but belongs in the sweeper PR with an explicit `kitty-setup.sh --apply` step and a new parity arm. `bin/cc-in-kitty` is unchanged — `:67-68` already honours `CC_TERM` correctly.

### Sweepers — what changes, what does not

- **Second PR, not this one**: `bin/cc-reconcile:190-191` (assignees skipped as `no-sid` because CC writes no `sessions/<pid>.json` for `--agent-id` children — 6/6 measured; synthesise identity from the `--agent-id <name>@session-<lead>` argv token, which `bin/cc-teardown:439-440` already parses and `bin/cc-classify` does not); `bin/cc-reaper:639` `delta=$((live-enum))` → set-diff of pane ids, not counts (stale `pane:null` rows cancelled a true blindness of 6 into a logged `delta=1`); `CC_REAPER_CLASSIFY_TIMEOUT_S=90` (109 timeouts in the Aug 3–4 window); the missing `cc-fired` stamp for assignees.
- **No change**: `scripts/worktree-gc.sh` (`:724-730` has its own independent gate chain; removals at `:687`/`:788` never pass `--force`); `bin/cc-reaper:511-514` (already refuses on dirty and says *"The PANE is still reaped either way"* — the principle this whole fix implements); `scripts/postland-verify.sh:371-379`; `hooks/lead-crash-watchdog.sh:279` (its 30-min marker-freshness window already does a generation stamp's job); `hooks/lib/session-writes.sh` (the attribution is correct — only its plumbing was dropped); `hooks/teammate-checkpoint.sh`.
- **Named, not fixed**: `com.claude.team-orphan-reaper` is a plist that was never `launchctl load`ed (absent from all 15 rows). Loading an unexercised reaper *into* this defect class is not a fix; file it.

---

## 4. THE TEST PLAN

**Every negative assertion must be `if grep -q X "$LOGF"; then echo …; false; fi`, never `! grep -q X || { … }`** — `scripts/ship-land.sh:1192-1224` runs `scripts/bats-assert-liveness.py` on the diff (exit 6), and `scripts/gate-select.sh:101` forces `tests/bats-assert-liveness.bats` on any `.bats` edit. The trap is already documented at `tests/teammate-auto-shutdown.bats:640-642`.

**The fixture that does not exist and must** (`tests/teammate-auto-shutdown.bats`): `shared_linked_worktree()` — `git init` a repo, `git worktree add` a *real linked* tree, N≥3 members in `teamcfg_shared` each with `joinedAt`, and crucially **a sibling-authored untracked file** as the only dirt (this is the live shape: 1 `??` from the lead). Plus `tx_leadmail()` emitting a user record whose content begins `<teammate-message teammate_id="team-lead">…shutdown_request…`. Plus **running the REAL guard**: `CC_REAP_GUARD_BIN=$REPO/scripts/reap-guard.sh` + `CC_REAP_RECORDS_DIR`. Today **30 of 39 tests skip reap-guard entirely** (the fixture `HOME` has no `scripts/reap-guard.sh`; `:774`) and the other 9 stub it to one exit code — so **no existing test can distinguish a WHO-refusal from a WHAT-refusal**, which is this fix's central discrimination.

| Change | RED-first proof (fails on pristine tree) | Positive control (stops a vacuous pass) |
|---|---|---|
| reap-guard shared+clean skips the dirty leg | New test: shared tree, dirt authored by a *sibling*, real reap-guard ⇒ assert `✓ closed pane` and assert `it2-calls.log` non-empty. On pristine: `DEFER dirty-tree` ⇒ no close. | **Same tree, dirt authored by THIS member** ⇒ `DEFER`, `[ ! -s "$D/it2-calls.log" ]`. If both close, the relaxation over-reached. |
| `--tree-verdict unknown` fails closed | Delete the member's transcript ⇒ `session_dirty_mine` rc 2 ⇒ assert DEFER. | The clean-transcript twin closes. A control that cannot fail proves nothing. |
| R-b `shared-no-refs` ⇒ REAP | Read-only member, no `refs/wip/<m>/**`, clean tree ⇒ assert close. On pristine: `DEFER no-products`. | Assert the **shared worktree still exists** after (`[ -d "$wt" ]`) and `git -C "$wt" status --porcelain` is byte-identical before/after. |
| `<teammate-message>` is not adoption | `tx_leadmail()` only ⇒ assert close. On pristine: `DEFER operator-adopted`. | **A genuine operator prompt on the same tree ⇒ HELD**, `[ ! -s "$D/it2-calls.log" ]`. This is the one control that keeps the 2026-07-24 incident class closed. |
| Identity pin | Seed `tmuxPaneId` for a window whose fg cmdline lacks `--agent-name <m>` ⇒ assert refusal + no close. On pristine: it closes. | Correct cmdline ⇒ closes. And a **generation-mismatch** arm: `--expect-generation` ≠ live `KITTY_PID` ⇒ refuse. Runnable safely with a second kitty (`--instance-group`, `CC_TERM_KITTY_TO`) — no restart of the live one. |

**Existing tests, disposition:**

- `tests/teammate-auto-shutdown.bats` **@521** (`:527` SURFACE grep, `:528` `SHARED cwd` grep, `:531` `[ ! -s it2-calls.log ]`) — **REWRITE, do not delete.** Measured RED under the candidate patch. Its stated premise ("a close here would be the ungated-close defect") is **false**: under the patch the close ran busy-marker, F1, tool-in-flight, checkpoint and the adoption belt, and logged `~ worktree kept (shared, not owned by mshared)`. It conflates *gating* with *removing*, which `:1130-1141` already separates. Keep `:531`'s absence check for a **WHO**-refusal; replace the SURFACE expectation with a close expectation for a **WHAT**-refusal. Deleting it wholesale would remove the only shared-cwd close-refusal pin in the corpus.
- **@648 `:661`** (own dirty file still defers) and **@666 `:673`** (cannot-tell keeps the defer) — **MUST STAY GREEN.** Both went RED under the blanket variant; that is the signal the relaxation over-reached. Gate the relaxation on `_sw_rc == 1` only, never on `!WORKTREE_OWNED` alone.
- `tests/reap-guard.bats:23` `[ "$n_ok" -eq 8 ]` — **bump to 12 in the same commit** as the new selftest arms, or the land goes red on a suite nobody touched.
- `tests/interactive-parity.bats:118-122` — re-run; it pins `ci_ ⇒ ce_`, which the two-file predicate change must preserve.
- **Unmeasured blast radius, must be run before landing**: `tests/cc-classify.bats` (:217, :249-250), `tests/cc-teardown.bats`, `tests/cc-reaper.bats` against the patched WHO predicate. Teaching the fleet that `<teammate-message>` is not a human also changes what counts as an operator-present session for the recycle/handoff rails — that is a second subsystem and it has not been examined.
- `scripts/teammate-reap-alarm.sh` / `tests/teammate-reap-alarm.bats` / `tests/cc-blockers-teammate-reap.bats` — no change needed **provided the new decision line is not spelled `defer …` or `⚑ SURFACE …`** (`:118-120` builds the denominator from those two literals).

---

## 5. THE OUTCOME ALARM

**The one check: assignee-pane residency, sampled from the world, joined on three independent sources, scheduled by launchd.** It reads `it2 session list` (window-id set) × every `~/.claude*/teams/*/config.json` member with an **integer** `tmuxPaneId` × `ps -ax -o command=` filtered on `--agent-name`, and emits per sample: members resident, members departed since the previous sample, and each resident member's age since its last `teammate-lifecycle.log` decision. **ALARM when ≥`MIN_EVENTS` distinct members have been resident past a threshold with `departed == 0`.**

Lives as `scripts/assignee-pane-residency.sh`, feeding `scripts/teammate-reap-alarm.sh` as the **numerator replacement for `:114`**, with a `com.claude.teammate-reap-alarm` plist — because today the alarm's only caller is `bin/cc-blockers:161`, and `cc-blockers` is **not in `launchctl list`** (15 jobs, none of them). It is pull-only, invoked when an agent happens to run `/ship`. That is why nobody noticed for nine days.

**Why it refutes all four prior premature victories, on the day each was declared** — every one was *true* and *insufficient*, and every one was measured against a defer-reason or an internal predicate rather than against the world:

| Declared | What was true | What residency would have read |
|---|---|---|
| 2026-07-25 `c69df3f2`/`157eca9b` "gate-unrunnable defers instead of closing ungated" | The ungated-close hole really did close | N resident, **0 departed** — from 15:58 that day, the first day of the outage |
| 2026-08-01 `bbe7ebbb` "the backstop needed one more event" | Verified: **no counter has reached 3 since** (min age of a value-3 file 49.20 h vs the fix at 49.1 h) | N resident, **0 departed** |
| 2026-08-03 `joinedAt` spawn-time | Verified: records now read `age_s` 262–407, not the 83% `age 0s < grace 300s` | N resident, **0 departed** |
| 2026-08-03 F1 attribution + `2f3bfc06` CC_TERM | Verified tonight: attribution clears **10/10**; CC_TERM pin is on `origin/main` and structurally sound | N resident, **0 departed** — measured right now, 12 resident |

It also survives the two blind spots the current metric demonstrably has, both proven tonight: **six panes closed with zero `✓ closed pane` lines**, and the log's last two lines asserting `Pane NOT closed` for panes that were gone. Residency counts a departure no matter which actuator caused it, and cannot be satisfied by a gate change, a backend swap, or a rerouted close. Keep the existing four-verdict discipline (`NOT-EXERCISED` is a distinct verdict, never `OK`) but compute `EVENTS` from the **join**, not from log greps — today `EVENTS < 10 ⇒ rc 0`, so "the fix worked" and "no teams ran" render identically.

---

## 6. THE DEPLOYMENT

**Everything this fix touches is a per-file symlink and goes live on the trunk fast-forward — except the one file I am deliberately not touching.** Verified this session:

```
~/.claude/hooks/teammate-auto-shutdown.sh  -> SYMLINK <repo>/hooks/teammate-auto-shutdown.sh
~/.claude/scripts/reap-guard.sh            -> SYMLINK <repo>/scripts/reap-guard.sh
~/.claude/hooks/lib/session-writes.sh      -> SYMLINK <repo>/hooks/lib/session-writes.sh
~/.claude/hooks/teammate-checkpoint.sh     -> SYMLINK <repo>/hooks/teammate-checkpoint.sh
~/.claude/bin/it2-kitty                    -> SYMLINK <repo>/bin/it2-kitty
~/.claude/bin/cc-in-kitty                  -> SYMLINK <repo>/bin/cc-in-kitty
~/.claude/bin/it2                          -> REAL FILE 11509B   (copy of bin/it2-wrapper; IDENTICAL today)
```

`~/.claude/bin/it2` is deployed by `copy_file` (`install.sh:527`; also `scripts/kitty-setup.sh:160-162`), and **`scripts/deploy-link-parity.sh:181` globs only `"$REPO"/bin/cc-*`** — `it2-wrapper` and `it2-kitty` are outside its map. It reported `299 linked · 0 actionable · ✓ every landed file is live` this session with that frozen copy in place. **Landed-but-dead with an affirming oracle** is the worst polarity available, which is exactly why the identity pin goes in `bin/it2-kitty` (symlinked) and not `bin/it2-wrapper`. If a future change *must* touch the wrapper, it needs an explicit `scripts/kitty-setup.sh --apply` step in the same PR **and** a new parity arm covering `install.sh`'s `copy_file` targets (`:340`, `:387`, `:405`, `:428`, `:520`, `:527`, `:609`).

**Liveness verification by content, for a future session** — one command, no trust in a parity report:

```
for f in hooks/teammate-auto-shutdown.sh scripts/reap-guard.sh hooks/lib/context-econ.sh \
         hooks/lib/cc-interactive.sh bin/it2-kitty; do
  diff -q "$HOME/.claude/$f" "$PWD/$f" >/dev/null && echo "LIVE  $f" || echo "STALE $f"
done; diff -q "$HOME/.claude/bin/it2" "$PWD/bin/it2-wrapper" >/dev/null \
  && echo "LIVE  bin/it2 (copy)" || echo "STALE bin/it2 (copy — run scripts/kitty-setup.sh --apply)"
```

Then confirm the fix is *exercised*, not merely present: `grep -c '✓ closed pane' ~/.claude/logs/teammate-lifecycle.log` must exceed 680, and the residency alarm must show a non-zero `departed`. A green suite is not evidence here — **the close path has produced zero closes in ten days, so this is an unrun program until a real pane goes away.**

---

## 7. RESIDUE — genuinely out of reach, named and bounded

- **Vendor: the third close path.** Something closed panes 403/405/407 at 00:42 (four `Session ended` in `~/.claude/logs/sessions.log` at 00:42:12–00:42:27) with **zero** lifecycle-log lines, and CC rewrote `config.json` to drop those members within minutes. Ruled out on disk: `teammate-auto-shutdown` (it logged the opposite) and `cc-teardown` (no record since 2026-07-31 15:01). Strongest remaining candidate, unproven: CC's own `killInProcessTeammate` → `memberRemoval` + `osTeardown` + `paneTeardown` (`swarm_in_process_kill`), which the binary documents as **non-blocking** — *"Not blocking the stop result on it; the backend kill continues in the background and the separate `claude --agent-id` process may still be running."* **Bound**: this actuator already closes our targets, so our fix may be partly redundant and its effect will be hard to attribute. **Experiment**: with the live 13-member team, sample `it2 session list` + `ps --agent-name` every 30 s and correlate departures against the lead's `TaskStop` calls — read-only, no pane touched. Do it before landing, or the alarm's first `departed` may not be ours.
- **Vendor: `AgentInput.isolation?: "worktree"`** (`/Users/chrisren/.claude-220/…/sdk-tools.d.ts:517-521`) — the literal remedy the hook prints at every SURFACE (`:837` *"Fix at spawn (give the member its own cwd)"*), three fields after the `team_name?` this investigation already quoted. **Untested on 2026-08-04**: whether it works on 2.1.220, whether the member's `config.json` then records its **own** cwd (which would make 218/218 of the population satisfiable and delete the gate problem entirely), what it writes into `tmuxPaneId`, and whether the GH #34645 / #48927 data-loss caveat in the operator's global CLAUDE.md still reproduces. **Bound**: it is the only candidate that fixes 100% of the population at the source; every fix in §3 is a downstream workaround whose *necessity* is unproven until this is measured. It is the single highest-value unrun experiment and it is cheap: spawn one throwaway assignee with `isolation:"worktree"` and read the resulting config.
  **RUN 2026-08-08 (backlog 4afd0515c83a) — and it does not rescue the population.** C1 above already
  refuted the teammate half: `isolation` passed *alongside* `name` silently demotes the spawn to an
  in-process subagent, so there is no member whose `config.json` could record its own cwd, and the
  218/218 hope dies there. What this run adds is the other half — passed *without* `name`, isolation
  works exactly as documented on 2.1.220: a real worktree, its own branch, and (since 72abcf14) a
  hook that now refuses to hand back one belonging to another repo. The GH #34645 / #48927 caveat did
  not reproduce in a single run, which is not evidence against a race. Treat this bullet as closed
  for the data-integrity question and unchanged for the gate question: every §3 fix stays necessary.
- **Vendor: `TeammateIdle` supply.** One emitter, turn-end only, no heartbeat. 98/155 members post-fix received ≤2 events against a `MAX_DEFERS` of 3. **We cannot make the harness emit more.** Bound: after this fix a member acts on its *first* qualifying event, so supply stops binding — but 161 counters currently sit at rung 2 on disk (`~/.claude/watchdog/defer-*.count`, 326 files, only reset by `rm -f` at `:884`), meaning **161 pre-armed ladders will act on their very next event under the new policy**. State that behaviour explicitly in the commit message; it is not a defect but it is a surprise.
- **Kitty cross-generation aliasing.** Confirmed link-by-link (per-process counter restarting at 1; no identity check at `it2-kitty:477`; positive-controlled close of a non-claude window; `cc-reconcile:273` makes an aliased row immortal) but the **composite has never been exercised** — kitty 613 has run 78.8 h and the kitty era began 2026-07-31, so no integer-keyed record has ever outlived the process that minted its id. **Bound**: hazard is 100% latent and the population is 12 live pane ids today. The identity pin in §3 closes it prospectively. A safe composite test exists and was not run: seed a scratch registry row with an id a second `--instance-group` kitty will reissue, point `CC_TERM_KITTY_TO` at the probe socket, and drive the close — blocked only because `bin/cc-teardown` exposes no registry-dir seam.
- **SIGHUP during an active turn.** Measured only on an idle REPL (1.373 s, clean flush). `Ps()`'s watchdog bounds shutdown at `max(5000, sessionEndHookTimeout+3500)` ms, 15000 ms on one branch — unmeasured. The actuator fires `CLOSE_GRACE_S=3` s (`:66`) after the decision with **no re-check that the member is still idle at that instant**. Bound: the idle→close window is unguarded by anything, in the current code and after this fix. Filing it is honest; closing it needs a re-read of `_tool_in_flight` inside the detached block at `:1113`.