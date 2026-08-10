# cluster-C-panes — triage vs origin/main @ 51bdb524 (2026-08-09 16:51 -0700)

Measured live state used as the decay oracle throughout (all read 2026-08-09 ~17:15, uptime 12h56m,
load 12.75):

| fact | value | how |
|---|---|---|
| iTerm2 | **NOT RUNNING** | `pgrep -x iTerm2` empty |
| live kitty panes | **17** (3 os-windows, 3 tabs) | `kitten @ ls` |
| live `claude.exe` | **9** | `pgrep -f` |
| live panes in wt-149789b69fc4 / wt-191d4d056c98 / wt-13d56549ece8 | **0 / 0 / 0** | `lsof -a -d cwd -c claude`, 0 cc-registry rows |
| registered worktrees | **425** | `git worktree list \| wc -l` |
| shared checkout vs trunk | **0 ahead, 19 behind, fast-forwardable** | `git merge-base --is-ancestor HEAD origin/main` |
| agent-browser daemons | **0** | `pgrep -f agent-browser` |
| Fable routing | **routable** (`➤ fable → next2, Fable 0%`) | `claude-accounts` |

The box rebooted ~12h ago. **That is the single largest decay event in this slice**: every item whose
body is "close pane N / close the ~20 panes in worktree W" is dead by reboot, and I verified each by
cwd + registry rather than by inference.

## Summary

counts: PRUNE 18 / UPDATE 10 / KEEP 26 / MERGE 0   (= 54)

## Verdicts

`a39d623f5381` | PRUNE | permission already landed: `Bash(kitten @ send-text:*)` present in BOTH `.claude/settings.json:6` and `~/.claude/settings.json:183`, alongside get-text/launch/close-window/ls (project file carries a `_why_kitten` rationale block).
`9cfd3fb7a6a6` | PRUNE | duplicate of a39d623f5381 — same permission, already present; `/tmp/allow-kitten-sendtext.sh` no longer exists.
`71a0edb3630d` | PRUNE | the ~20 panes are gone: 0 live `claude` with cwd `wt-149789b69fc4`, 0 cc-registry rows naming it, box rebooted 12h56m ago. (Worktree DIR survives → feeds M-panes-2.)
`df9454d4a542` | PRUNE | same, `wt-191d4d056c98`: 0 live cwds, 0 registry rows. Panes 351/353/354/356/357/358 and the keeper 352 are all gone.
`4d37a4dca4f6` | PRUNE | same, `wt-13d56549ece8`: 0 live cwds; pane 460 is not among the 17 live panes.
`c17369964b30` | PRUNE | that origin pane is not among the 17 live panes; the cloud-2way successor's worktree survives but no session holds it.
`0dc334a97dc0` | PRUNE | premise fully refuted — **iTerm2 is not running on this box**; registry row `56A3C488*` absent.
`b2787f38dd80` | PRUNE | premise fully refuted — iTerm2 not running, fleet migrated to kitty. "154% CPU / 8.4GB after 14d uptime" cannot be true of a dead app.
`54ef90be1459` | PRUNE | premise refuted — `claude-accounts` now reports `➤ fable → next2 · Fable 0% ↻5d10h · weekly 9%`, i.e. Fable IS routable, so "the deep-dive CANNOT RUN" is false. The three stranded panes are gone with their worktrees (`inertness-generator`, `lakehouse-lecture` both absent from disk).
`62023c187144` | PRUNE | **the fix LANDED**. `scripts/lib/worker-claim-gate.sh:328` now has a `*status=done*)` arm inside `verdict=noop-status` that REFUSES with `basis=done-latched` ("The work is finished; STAND DOWN…"), exonerates the finisher, and fails OPEN on an unreadable holder. OPEN/BLOCKED keep the old behaviour verbatim — exactly the three-valued split the item prescribed.
`16618dfe7574` | PRUNE | fix LANDED (`ab6b99ef fix(cc-await-ping): one cached pid convicted a live pane`). `_owner_dead()` (bin/cc-await-ping:414) now requires the pid oracle **AND** a corroborator: `_pane_gone` + `_cwd_occupied`, with UNKNOWN transport failing closed so exit 5 became strictly harder to reach.
`a116d60af388` | PRUNE | fix LANDED and **names this item id in the shipped code**: `_veto "its cwd is held by a LIVE session under a DIFFERENT pane id (the id was renumbered underneath the registry — a116d60af388)"` (bin/cc-await-ping:~437).
`5b77e20d9db6` | PRUNE | explicitly refuted on trunk. `3c123bfc docs(await-ping): exit 144 is an EXTERNAL process-group SIGTERM — not SIGURG`; bin/cc-await-ping:243 cites this item id: "reads 144 as 128+16 ⇒ SIGURG. That is WRONG on the signal (SIGURG's default action is IGNORE, so bash cannot die from it)". Its correct half (external kill) + the F-2 "say it on a channel the lead acts on" fix landed (`e186b255`). Live remainder = b38279c10c55.
`258dddc54a02` | PRUNE | the discriminator it existed to run is moot — the cause is settled (`kill -TERM -<pgid>` → 144 with si_pid captured, per the header at bin/cc-await-ping:243-246), so "run it under setsid to separate group-kill from reaper" no longer separates anything. Its portable-detach datum survives inside b38279c10c55.
`5996271339eb` | PRUNE | **superseded, and landing it now would be a regression.** `937772ee fix(recycle): the probe typed on "I can't find CC" — and expect hides CC from the pane's tty` landed on trunk 2026-08-06 21:10 — 36 minutes BEFORE this item was filed (21:46) — with the same defect and same fix as branch commit `52989b58`. `52989b58` is not an ancestor of trunk and its branch now diffs **467 files / 78,855 deletions** against origin/main.
`8452b79a0d6f` | PRUNE | refuted on **both** sides it claimed were inert: wired in `~/.claude/settings.json:828` (Stop) and `:868` (UserPromptSubmit); `~/.claude/cc-beats` holds **1184** beat files; read side exists (`bin/cc-cloud`, `hooks/lib/cc-beat.sh`).
`7b6aca24df81` | PRUNE | `3451b711 feat(reaper): garbage arm` is an ancestor of trunk; `garbage_sweep()` at bin/cc-reaper:310 is default-ENABLED (`CC_REAPER_GARBAGE:-1`). The manual relief run is moot — the reboot cleared the residue anyway.
`a6841526a14c` | PRUNE | the one-off is moot: pane 702's row no longer names pid 60701/session ba3e84eb (it now names 33728 / cca8d930), and pane 702 is not among the 17 live panes. Note the replacement pid 33728 is ALSO dead — the *class* is real but is exactly what a116d60af388's landed corroborator fix now handles.

`9e2890ff3e1a` | UPDATE | **the operator gate is gone and nobody noticed.** The item's blocker was "2 commits AHEAD, so a fast-forward is refused, and moving a shared checkout's main is a destructive history op needing your call". Measured today: shared checkout is **0 ahead / 19 behind**, `git merge-base --is-ancestor HEAD origin/main` succeeds — a plain fast-forward. `5dbaf901` and `a33e854f` are no longer on HEAD. Should now say: *the live `~/.claude` layer is 19 commits stale; the fix is a non-destructive `git pull --ff-only` in the shared checkout, agent-drivable, no operator decision required.* This is the 🚀 rung and it gates everything else in this slice (most of `bin/ hooks/ scripts/` are per-file symlinks into that checkout).
`2224128627d0` | UPDATE | **cause RESOLVED — the investigation is over, an activation is what remains.** `fe6cd42a docs(research): /goal is deleted at every Stop by a background bash, not by kitty`: CC removes the goal's prompt hook from the Stop registry whenever `taskRegistry` holds a non-terminal `local_bash` task, then re-adds it in a `finally` — so the registry reads correct before and after and is wrong only *during* the Stop. **`cc-await-ping --timeout 14400` is exactly such a task, and this box tells every session to arm one.** Both of the item's live hypotheses are explicitly REFUTED in that doc (kitty-vs-iTerm2; steered-stop — "steering changes *when* Stop is reached, not whether the handler runs"). Remedy `735a2466 feat(goal-inert-watch)` landed but its Stop registration is **staged**, not live (`migrations/0005-goal-inert-watch-registration.sh`).
`dea13b7385c5` | UPDATE | cleanup half DEAD (0 live sessions in wt-149789b69fc4). Mechanism half PARTLY fixed and still live: `--untracked-files=no` now means a sibling's *untracked* litter no longer blocks a self-close (handoff-fire.sh:~4766), and `--dirty-owner successor` exists — but it **requires `--successor`**, so a fired peer that never fired a successor still cannot express "the dirt is a live SIBLING's tracked work; close the pane and touch nothing". Should now say: the third verdict is needed only for TRACKED sibling modifications, and `--dirty-owner sibling` (no `--successor` required, liveness-verified) is the shape.
`d90bbcd9e01f` | UPDATE | **the SPAWN half LANDED, the EXISTING-PANE half did not.** Landed: `--keep-focus` on the launch (bin/it2-kitty:599) and `deliver_argv` argv delivery with a pickup-ack + tri-state `pane_exists` (:318-340), per `fda70147 fix(handoff): the fired pane's command is argv, never keystrokes at a shared prompt`. Still live: the `run`/`send` verbs for an ALREADY-EXISTING (non-armed) pane fall through to a bare `kt send-text --match id:$SESSION … || exit 1` at :741 and :750 — the item's own measurement (kitty send-text exits 0 on `--match id:999999`) makes that `|| exit 1` dead code, and there is still no nonce echo-verify. `it2_type_verified` remains private to handoff-fire.sh (`scripts/typed-send-lint.sh:15` still documents it that way) — the shared-helper extraction 270106134cc8 prescribes has not happened.
`c32dd2ada61f` | UPDATE | attribution **did** land (`hooks/completion-assert.sh:203+`, `_ca_mine` covers both `dirty` and `unlanded` legs) — but **this item's exact case survives it**. Exoneration on zero recorded writes fires ONLY for a *confirmed Agent-Teams assignee* (:296-301: `_ca_assignee || return 2`); a MAIN session on a read-only turn — precisely `claude-infrastructure-323` — takes `rc 2 / cannot tell ⇒ stay strict` and is still convicted for a peer's commits. `grep -i 'LIVE-PEER\|peer-owned'` over the hook returns **nothing**. Should now say: the remaining gap is the write-free MAIN session in a shared checkout, and the fix is either author-session attribution of `trunk..HEAD` or a LIVE-PEER-OWNED terminal state.
`bc50117059ac` | UPDATE | substantially landed: `bin/cc-spawn-verify` is on trunk (`399ed0da feat(spawn-verify): the fourth state — a live agent that will never proceed`; `735c3c79` re-keyed the detector on the transcript after the prescribed anchor was absent on 23/23 healthy panes). Remaining and unstated-as-done: the ORDERING the item specifies (handoff successor FIRST — no surviving observer; then team panes; subagents last) and the pairing with deadline reconciliation.
`d8f8987f79ca` | UPDATE | **premise refuted — there is no plist to install.** `git ls-tree -r origin/main launchd/` lists 25 plists + 3 under `launchd/staged/` (lead-reconciler, relogin, scratchpad-reaper); **none** is a residency/assignee plist. Only `scripts/assignee-pane-residency.sh` + `tests/assignee-pane-residency.bats` exist. The work is "build and stage the plist", not "flip a manifest row staged→run".
`898f8eafb809` | UPDATE | still valid as an operator call, stale on its numbers: `~/.claude/logs/devserver-gc.last` now reads `verdict=none act=0`, not the cited `reaped=3 kept=2`. Plist confirmed still observe-only ("There is deliberately no DEVGC_ACT in this plist"). Two days of the requested clean-cadence have elapsed.
`f0283c35130e` | UPDATE | premise intact, figure stale: live agent-browser daemons = **0** today (reboot), not 42; and no reap/lifecycle for them exists — `grep -rn agent-browser bin/cc-reaper scripts/*.sh` hits only `scripts/unattended-path-lint.sh` (a PATH lint, not a reaper). Re-measure before sizing.
`1858fa6bcbc0` | UPDATE | **no longer operator-only.** Its stated blocker was the permission the classifier intermittently denied — that permission is now allowlisted in both settings files (see a39d623f5381), so `scripts/cloud-websetup-drive.sh` can drive the TUI unattended. Countervailing: `2fb9ed78 docs(cloud): G5 was graded on the parts that were built — the fire path has no cloud create`.

`bb2495b098b8` | KEEP | verified: `ls ~/.claude/skills` = **35** (matches the item's denominator), `config/live-only.manifest` is on trunk (the declaration+witness mechanism it proposes reusing), and no skills/-scoped auditor landed. *Not a pane item — see Notes.*
`5bb6555f22df` | KEEP | verified live: `scripts/lib/worker-claim-gate.sh` still resolves identity via `_cc_wclaim_ancestor_pid()` (:161-173) walking to the nearest `claude|claude.exe|claude-*` ancestor, deliberately not `$PPID`, with **no** `--agent-id` / subagent exclusion anywhere in the file. A read-only subagent still takes a lease.
`5fc785794b5a` | KEEP | verified live: `host="${CC_WCLAIM_HOST:-…}"` (:274) and `ident="$host-$pid"` (:281); no use of `--parent-session-id`. A teammate spawn still steals its own lead's lease, and the refusal text still tells the LEAD to stand down.
`e43e95c0ad18` | KEEP | no landing found for teammate-cwd inheritance; it is the mechanism underneath 5fc785794b5a and c32dd2ada61f (every member reads the LEAD's tree).
`bffbce207f12` | KEEP | verified verbatim: `hooks/agent-teams-enforce.sh:78-80` still `CC_ADMIT_LOAD_TERM=off cc_capacity_admit agent-tool "…spawn"`; `CC_SPAWN_ROOT`/`CC_SPAWN_DEPTH` appear nowhere in the tree. Narrowed but NOT retired by 62023c187144's landing — that fix bounds fan-out onto a *done* item only; an OPEN item's fan-out is still unbounded. The item's own "FIRST STEP IS A PROBE, NOT CODE" is still unrun.
`9a88cb04dab2` | KEEP | verified: **zero** `cc_capacity_admit` occurrences in `bin/it2-kitty`. `scripts/handoff-fire.sh:3408` confirms the asymmetry — "Those four are now gated by the SIBLING term, scripts/lib/capacity-admit.sh" (the fire sites), while the split/os-window spawn sites are not.
`93a9f880b6fe` | KEEP | verified: `successor_engaged()` (scripts/handoff-fire.sh:2103) has no `--resume` / transcript-growth awareness; the abort text and the only escape (`--successor-assume-engaged`, which "skips ONLY this half") are unchanged at :4750-4756.
`1b19ab3096d2` | KEEP | no lead-side fired-worktree reaper landed (`git log --grep='strand|land-before-ping|fired.*worktree'` since 2026-08-09 → empty). Note the cited recovery sha `24dc168c9` is **not an object in this repo** (bs-footer-motion is elsewhere) — the mechanism claim stands, the sha is unverifiable here.
`4b9d5e93b40a` | KEEP | `8efd363b docs(capacity): Phase E — headless is free` is a docs landing; the cc-registry pane-UUID keying itself is unchanged. Still blocks S6.7 Phase E.
`b521cb445465` | KEEP | nothing explains a 04:39Z closer. The teardown fixes that postdate it (`4fd818ea`, `23d75325`) are about a teardown *reporting* wrongly, not about an unrequested close. Death was verified on three axes by the original coordinator; I could not refute it.
`c7e61d079c26` | KEEP | `docs/plans/TERMINAL_AGNOSTIC_L3_L4.md` on trunk, `status: open`, frozen scope names "scale past the **~38-pane physical ceiling**" — directly on the operator's pain axis.
`d4fa449e3895` | KEEP | `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md` on trunk, `status: open`. This is the canonical carrier of the known-open class "kitty: assignee/subagent panes never self-close".
`0ab311dc9115` | KEEP | `hooks/teammate-auto-shutdown.sh` around :830-845 unchanged in the direction the item names (the `_tool_in_flight` defer and the reap-safety gate are there; the SURFACE's spawn-side prescription is untouched).
`158d53aaa3b1` | KEEP | `docs/proposals/ARMED_SUCCESSION_LIFECYCLE.md` on trunk; no landing for supersede-on-arm, watcher trap/events, or a `SHIP_POLICY` ledger field (`grep SHIP_POLICY` over wrap-ledger.sh / cc-backlog → empty).
`b38279c10c55` | KEEP | the sender is still unestablished and is now the ONLY live remainder of the exit-144 trio. bin/cc-await-ping:235 states the constraint: "an SA_SIGINFO recorder is the only thing that yields si_pid, and 144 proves only that the signal came from outside the harness". No recorder was built. **Sharply raised in value by fe6cd42a** — see Notes.
`66ec1b04f050` | KEEP | verified: `mailbox_alias_write "$own_pane" "$own_sid"` still fires on every boundary (hooks/mailbox-drain.sh, the `M1 addressing repair` block). The item's actual question — does any resolver read the TIP? — is unanswered.
`0eae16398acd` | KEEP | both files still on disk and unread: `~/.claude/mailbox/359.md` (2 lines) and `~/.claude/mailbox/dead-letter/359.md`. Cheapest item in the slice.
`ef5f9ea26926` | KEEP, and the blast radius GREW | verified the guard is still blind by construction: `worktree_cleanup()` in `bin/cc-reaper` gates on `git status --porcelain` (**no `--ignored`**, so gitignored files are never reported) and then runs `worktree remove --force`. The line moved (item cites `:427`; it is now ~`:630`) but the predicate is unchanged. Live population is now **425 registered worktrees**, up from the item's "93 would remove".
`0b4d4e8a1889` | KEEP, freshly validated | `5da21949 revert(wrap-ledger): withdraw the --machine memo — its consumer suite refutes it` landed the same day: the whole-ledger cache measured a real 60→27 subprocess cut but went 3 red on tests/wrap-ledger.bats, all three ⛔-rung, because *"a directory's mtime does not move when a file's content changes"*. That revert is this item's proof — "cache the git-derived fields, always run the two bounded store forks, re-derive RUNG from the union" is exactly the shape the revert leaves open.
`bd2f7c2209fa` | KEEP | verified in the subject's own comments: `hooks/boundary-handoff.sh:99` is still `T="${CC_BOUNDARY_T:-73}"`, `CC_BOUNDARY_T_IDLE` does not exist, and :238 says verbatim "waiting-recycle.sh owns T_IDLE=35 but runs on PostToolUse:Bash — … **Nothing implemented that**".
`15b99887cd5e` | KEEP | verified verbatim: `hooks/validate-bash.sh:228` builds `CMD_NOQ` by stripping only quoted runs, and `:229` splits it on `sed 's/[&|()]/;/g'` — so `(pkill|killall)` inside a heredoc-fed commit message still yields a `pkill`-leading fragment and still denies the commit.
`b0a237b76793` | KEEP | `docs/activation/pending-activation/32-cc-roles-kitty-normalise-activate.sh` is still on trunk in the pending queue; no `cc-roles` wiring in `~/.claude/settings.json`.
`f6cc5c79885b` | KEEP | `docs/plans/HOOK_CHAIN_COST.md:30` and `:356` carry R-7 on trunk, status **unmeasured**, and name the blind population precisely (match-all matchers: teammate-checkpoint, cc-permission-beacon, mailbox-drain).
`2029c52b8a32` | KEEP, with a provenance warning | premise stands. **But its cited "Landed evidence a7ededda+96c2932a" is NOT on trunk** — both are real commits, neither is an ancestor of origin/main. So its own evidence is stranded on a branch. *Not a pane item — see Notes.*
`9381bf26d754` | KEEP | pure operator value call (cut/keep two banner emote candidates); nothing in the tree decayed and no gate can make it. *Not a pane item — see Notes.*
`bbbedc12cb8b` | KEEP | verified live: `map --allow-fallback=shifted,ascii cmd+e open_url_with_hints` is still in `config/kitty.conf` with its ⌘E-probed-FREE rationale intact. Operator value call.

## Master item(s)

### M-panes-1 — A pane cannot be born unbounded and cannot die on its own; close that loop

**Encompasses:** `9e2890ff3e1a` `bffbce207f12` `9a88cb04dab2` `5fc785794b5a` `5bb6555f22df`
`e43e95c0ad18` `bc50117059ac` `d90bbcd9e01f` `d4fa449e3895` `0ab311dc9115` `dea13b7385c5`
`93a9f880b6fe` `158d53aaa3b1` `4b9d5e93b40a` `66ec1b04f050` `1b19ab3096d2` `b38279c10c55`
`b521cb445465` `c7e61d079c26` `c32dd2ada61f` `2224128627d0` (21)

**Why one effort.** One root cause with two faces, and both faces are the *same* missing thing: **a
pane's identity is never established, so nothing can bound its birth and nothing can authorise its
death.** Every item above is a place where identity is absent, wrong, or unreadable:

- *Birth is unbounded because nothing counts spawns.* The one Agent-tool chokepoint runs with the
  load term explicitly OFF (`bffbce207f12`), the split path has no admission at all (`9a88cb04dab2`),
  and the lease that should refuse a duplicate is keyed on `host-pid` of the nearest claude ancestor
  — which is the *child's* pid for a teammate or subagent, so the gate steals the lead's own lease
  instead of stopping the duplicate (`5fc785794b5a`, `5bb6555f22df`, `e43e95c0ad18`).
- *Death is unreachable because self-close cannot name the state it is in.* Sibling tracked dirt has
  no verdict (`dea13b7385c5`), a resumed successor reads as never-engaged (`93a9f880b6fe`), an
  assignee never retires at all (`d4fa449e3895`, `0ab311dc9115`), and the succession contract's
  durability leg is unenforced so a "finished" peer strands commits (`1b19ab3096d2`).
- *Peers cannot tell live from dead, so neither side can act.* The registry is keyed on a pane UUID
  that renumbers underneath it (`4b9d5e93b40a`, `66ec1b04f050`), and the wake path that would carry
  the retirement signal dies to a sender nobody has identified (`b38279c10c55`, `b521cb445465`).
  `2224128627d0` is the same organ seen from the other side: the 4-hour `cc-await-ping` watcher every
  session arms is *itself* what silently deletes the `/goal` Stop hook (`fe6cd42a`), so one background
  job is simultaneously the wake path that keeps dying and the reason a stop-condition never fires.
  Fixing the watcher's lifecycle is one change that resolves both.

`9e2890ff3e1a` is step 0 rather than a peer: most of `bin/ hooks/ scripts/` are per-file symlinks
into the shared checkout, which is 19 commits behind trunk **right now** — so every fix below is
inert until it fast-forwards, and three items in this slice (16618dfe7574, a116d60af388, 62023c187144)
were filed against defects that were already fixed on trunk but not yet live.

**Impact, argued from evidence.**
- **This is the pane-count generator.** The measured meltdown shape is 224 Agent-tool spawns in one
  fan-out and ~25 panes/10min for a single item, admitted by a gate whose own refusal text says
  "reduce the fan-out width" — an axis it has no sensor for. That is the mechanism behind 4 kernel
  watchdog panics. Nothing else in this slice reduces *live* pane count; the reaper items reduce
  *residue*.
- **It retires 20 of my 36 survivors**, plus the three already-landed PRUNEs prove the surface is
  actively converging (a116d60af388's fix cites the item id in shipped code).
- **It touches enforcing stores, not documents**: `hooks/agent-teams-enforce.sh` (a PreToolUse gate),
  `~/.claude/settings.json`, `scripts/lib/worker-claim-gate.sh` (a write gate), `bin/it2-kitty` (the
  spawn transport), cc-registry.
- **It unblocks a named plan**: `TERMINAL_AGNOSTIC_L3_L4.md` scopes past the ~38-pane physical
  ceiling, which is unreachable while spawns are uncounted.

**DoD.** Shared checkout fast-forwarded and the live layer verified by content. The Agent-tool
chokepoint counts spawns per originating item (probe-first: prove env propagates into in-process
subagents AND kitty-launched assignees before writing the design). `bin/it2-kitty`'s split/os-window
sites call `cc_capacity_admit`. The lease keys on the session that owns the work, not the nearest
claude pid — a subagent takes no lease at all. Self-close has a verdict for sibling-owned tracked
dirt and for a `--resume`d successor (engagement asserted by transcript GROWTH past the pre-resume
row count). The already-existing-pane typing path shares one verified helper with an echo-verify.
All landed on trunk, gate-green, and observable in the live layer.

**Falsifier** (exit 0 ⇒ this whole effort is no longer needed):

```
R=~/Development/claude-infrastructure; git -C $R merge-base --is-ancestor origin/main HEAD \
 && git -C $R show origin/main:hooks/agent-teams-enforce.sh | grep -q 'CC_SPAWN_DEPTH\|CC_SPAWN_ROOT' \
 && git -C $R show origin/main:bin/it2-kitty | grep -q 'cc_capacity_admit' \
 && git -C $R show origin/main:scripts/lib/worker-claim-gate.sh | grep -q 'agent-id\|parent-session-id' \
 && git -C $R show origin/main:scripts/handoff-fire.sh | grep -q 'dirty-owner sibling'
```

**First move.** Run the probe `bffbce207f12` names as its own first step and which has never been
run: does an env var stamped on a session actually propagate into (a) an in-process Agent subagent
and (b) a kitty-pane-launched assignee? The entire spawn-budget design is vacuous if it does not, and
that is a 10-minute measurement. Do it in the shared checkout *after* the fast-forward, so the probe
runs against live bytes.

**Order.**
1. `9e2890ff3e1a` — fast-forward the shared checkout (`git pull --ff-only`; 0-ahead confirmed today, no operator call needed). Everything else is inert before this.
2. `bffbce207f12` — the propagation probe, then the spawn-root/depth design. Gates the two below.
3. `9a88cb04dab2` — wire `cc_capacity_admit` into it2-kitty's split/os-window sites (cheap, independent, immediate load relief).
4. `5fc785794b5a` → `5bb6555f22df` → `e43e95c0ad18` — one fix, three faces: re-key the lease off the owning session; subagents take none.
5. `d4fa449e3895` → `0ab311dc9115` → `dea13b7385c5` → `93a9f880b6fe` — the self-close verdict set, plan-first (the plan is on trunk and open).
6. `4b9d5e93b40a` → `66ec1b04f050` — registry identity; prerequisite for 7.
7. `b38279c10c55` → `b521cb445465` → `2224128627d0` — the SA_SIGINFO recorder (the only instrument that can name the killer in either case), then the watcher-lifecycle decision it enables: `2224128627d0` also needs its already-built remedy activated (`migrations/0005-goal-inert-watch-registration.sh` is staged, not live).
8. `1b19ab3096d2` → `bc50117059ac` — the succession contract's two unenforced ends (start-ack ordering, land-before-ping).
9. `c32dd2ada61f` — attribute `trunk..HEAD` by author-session, or add LIVE-PEER-OWNED.
10. `d90bbcd9e01f` — extract the verified-typing helper (last: the spawn half already landed, so this is the smaller remainder).
11. `158d53aaa3b1` · `c7e61d079c26` — ratify the lifecycle design and advance the L3/L4 plan on top of the now-working substrate.

---

### M-panes-2 — Nothing owns what a dead session leaves behind, and one arm deletes what it should keep

**Encompasses:** `ef5f9ea26926` `f0283c35130e` `898f8eafb809` `d8f8987f79ca` `0eae16398acd` (5)

**Why one effort (and why it is NOT M-panes-1).** Different surface and opposite time-direction:
M-panes-1 is *lifecycle* (prevent the pane), this is *post-mortem* (collect what the pane left). They
share no file — this one lives entirely in `bin/cc-reaper`, `launchd/`, and the mailbox — and it can be
driven to completion without touching a single spawn or self-close path. The shared root here is that
**the residue arms are asymmetrically wrong: the one that runs deletes too much, and the ones that
would run were never installed.**

**Impact, argued from evidence.** `ef5f9ea26926` is the highest-severity item in my whole slice and
it is a **data-loss** defect, not a hygiene one: `worktree_cleanup()` guards with
`git status --porcelain`, which by construction never reports gitignored files, then runs
`worktree remove --force`. A worktree holding only `secrets.env` therefore reads clean and is
deleted at exit 0. The exposed population is **425 registered worktrees today** (the item was filed
citing 93). Every other member is a missing owner: no reaper knows about agent-browser daemons, the
dev-server reaper is built but disarmed, and the assignee-residency alarm has a script and a test but
— refuting its own item — **no plist at all**.

**DoD.** `worktree_cleanup` refuses (or warrants + ledgers) on `git status --porcelain --ignored`,
with a control that fails on the pre-fix predicate. Worktree count back under a stated ceiling by a
sweep that provably preserves gitignored content. agent-browser daemons have a reap owner.
devserver-gc armed or explicitly declined with the decision recorded. The residency plist built,
staged, and its manifest row truthful. The two pane-359 dead letters read.

**Falsifier:**

```
R=~/Development/claude-infrastructure; git -C $R show origin/main:bin/cc-reaper | grep -q 'porcelain --ignored' \
 && [ "$(git -C $R worktree list | wc -l)" -lt 50 ] \
 && git -C $R ls-tree -r origin/main --name-only launchd/ | grep -q 'residency'
```

**First move.** Reproduce the destruction on a throwaway worktree containing only a gitignored file
and confirm `git status --porcelain` reports empty while `--ignored` reports it — the one-line
predicate change plus a control that fails on the old predicate. Do NOT run a sweep over the 425
before that guard lands.

**Order.** 1. `ef5f9ea26926` (guard first — it is the only member that can destroy something) ·
2. the bounded worktree sweep it makes safe · 3. `f0283c35130e` (re-measure the daemon count first;
today it is 0) · 4. `d8f8987f79ca` (build the missing plist) · 5. `898f8eafb809` (arm or decline) ·
6. `0eae16398acd` (two lines, do it whenever).

---

### M-panes-3 — The operator's own queue: four calls no gate can make

**Encompasses:** `bbbedc12cb8b` `9381bf26d754` `b0a237b76793` `1858fa6bcbc0` (4)

**Why a third, and why not folded.** These are not engineering work and folding them into M-panes-1/2
would misrepresent them as agent-drivable, which is the exact defect the `👤`-vs-`✅` split exists to
prevent. Two are value judgments no gate can make by construction (keep ⌘E bound to
`open_url_with_hints` vs. move it behind a chord; cut-or-keep two banner emote candidates whose own
verifier measured movement% *not* to track legibility). One is a staged activation script sitting in
the pending queue. One (`1858fa6bcbc0`) is included because **its operator-only status just expired**
— its blocker was the `kitten @ send-text` permission, now allowlisted in both settings files, so it
should be re-classed as agent-drivable rather than left in the operator pile.

**Impact.** Small but non-zero, and it is *unblocking* impact: `b0a237b76793` and `1858fa6bcbc0`
each gate downstream work, and clearing all four takes one sitting. Keeping them visible as a
counted `👤` line rather than buried in prose is the whole point.

**DoD.** ⌘E ruled on and `config/kitty.conf` reflects the ruling. The two emote candidates cut or
kept. Activation 32 run and out of `pending-activation/`. Account links driven to completion
unattended and `1858fa6bcbc0` re-filed as agent work.

**Falsifier:**

```
R=~/Development/claude-infrastructure; [ ! -f $R/docs/activation/pending-activation/32-cc-roles-kitty-normalise-activate.sh ] \
 && ! git -C $R show origin/main:config/kitty.conf | grep -q '^map .*cmd+e open_url_with_hints'
```

**First move.** Re-class `1858fa6bcbc0` off the operator pile (the permission it waited for landed),
then present the ⌘E and emote calls as two yes/no questions in one message.

**Order.** 1. `1858fa6bcbc0` (re-class, then drive) · 2. `b0a237b76793` · 3. `bbbedc12cb8b` ·
4. `9381bf26d754`.

## Notes for the lead

**1. The strongest cross-cluster finding in my slice: the goal-inert bug and the exit-144 bug are the
same background job.** `fe6cd42a` establishes that CC removes the `/goal` Stop hook whenever
`taskRegistry` holds a non-terminal `local_bash` task — and names `cc-await-ping --timeout 14400` as
exactly that task, armed by *every session on this box*. So `2224128627d0` (my slice) and the
cc-await-ping items are one causal story, and the 4-hour watcher is implicated on both ends: it
silently disables `/goal`, and it is itself being killed by an unidentified group-TERM
(`b38279c10c55`). **If any other cluster holds items about `/goal`, Stop-hook registration, or the
14400s watcher, they belong with `b38279c10c55` — and the design question "should every session arm a
4-hour background bash at all?" is not filed anywhere I could find.** Worth minting.

**2. Six items in my slice are not pane items and should be re-homed.** I gave each a verdict, but
the lead should move them to the cluster that owns the surface rather than let my masters claim them:
`bb2495b098b8` (skills/live-layer versioning → deploy/link-parity), `2029c52b8a32` (per-coalition
memory footprint → machine/capacity), `f6cc5c79885b` (hook-chain cost census → hooks),
`15b99887cd5e` (validate-bash guard → hooks/testcorpus), `0b4d4e8a1889` (wrap-ledger perf → landgate),
`bd2f7c2209fa` (idle-recycle Stop carrier → session). All are KEEP with verified premises, so
re-homing loses nothing. **I deliberately left these six OUT of all three masters** — so my 36
KEEP+UPDATE map to 30 encompassed + these 6 unencompassed-by-design. If another cluster's master
already covers them, prefer that one; if none does, they need a home and should not be lost.

**3. Landmine — do not land branch `fix/recycle-pane-probe-fail-safe` (`5996271339eb`).** It looks
like a clean "gates green, tree clean, just needs a land" item and it is not: the same fix already
landed independently as `937772ee`, 36 minutes before the item was filed, and the branch now diffs
**467 files / 78,855 deletions** against origin/main. Landing it would delete `tools/banner/recycle.py`,
`tools/timeline/gen.py` and much more. Any cluster holding "unlanded branch" items should apply the
same content check (`git diff --stat origin/main <branch> | tail -1`) before treating a stale green
branch as landable.

**4. Provenance warning on `2029c52b8a32`.** It cites "Landed evidence a7ededda+96c2932a" — both are
real commits and **neither is an ancestor of origin/main**. Whoever holds the capacity/machine cluster
should not treat that item's measurements as landed fact.

**5. Reboot as a decay oracle.** 8 of my 18 PRUNEs are "close pane N" items killed by a ~12h-ago
reboot. If other clusters carry pane/session-id-specific cleanup items, the same check retires them
cheaply: `lsof -a -d cwd -c claude | grep <worktree>` plus `ls ~/.claude/cc-registry/<pane>.json`.
**But note the asymmetry the reboot does NOT resolve:** the *worktrees* those panes held all still
exist (425 registered), so the residue survived the event that cleared the panes. A PRUNE on the pane
is not a PRUNE on its worktree.

**6. Three items in my slice were fixed on trunk but filed anyway** (`62023c187144`, `a116d60af388`,
`16618dfe7574` — one of which is cited *by item id* in the shipped code). All three were filed while
the live `~/.claude` layer ran 19–21 commits behind trunk. That is not a filing-discipline problem, it
is `9e2890ff3e1a`: sessions are measuring the live layer and filing against bytes trunk already
replaced. Expect the same false-positive class in every other cluster, and expect the
fast-forward (M-panes-1 step 1) to retire more items than it appears to.
