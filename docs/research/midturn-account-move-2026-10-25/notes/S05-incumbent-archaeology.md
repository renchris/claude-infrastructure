# S05 — Incumbent archaeology: the restart-based move subsystem, its gates, its casualties, and the credential-swap graveyard

Slot S05-incumbent-archaeology. Written 2026-10-25 (~07:00-07:40Z, 02:00-02:40 CDT) in worktree
`/Users/chrisren/Development/.worktrees/research/midturn-account-move` (branch
`research/midturn-account-move`, HEAD `bfe8025ff`). Everything I ran was read-only. The only file I
wrote is this one; `/tmp/mtam/S05/` was created but stayed empty. I read no credential or token, ran no
`security` command, typed into no pane, ran no cc-lr mutation, and launched no Claude process.

Labels: **[M]** measured (I name the command), **[R]** read from a file (`file:line`) or from the
extracted binary source (byte offset), **[C]** cited from a prior doc's own measured figure (I did not
re-measure it), **[E]** estimated (I name the method).

---

## 0. Answer first

1. **The incumbent cannot move a session that is working, by construction.** Every path ends at
   `handoff-fire.sh --recycle`. It types `/exit`, waits for the shell, and types a launcher that runs
   `claude --resume <same uuid>` under the target `CLAUDE_CONFIG_DIR`. `/exit` interrupts an in-flight
   turn and nothing of that turn is persisted (`scripts/handoff-fire.sh:20757-20759`). So the census
   turns every sign of live work into a `wait:`/`hold:` row. The worker then polls a shared census and
   needs **two consecutive "move" snapshots** (`lr-move-worker.sh:212-258`). An operator who answers
   within seconds never produces two.
2. **Measured tonight [M]:** batch `20261025T063826Z-next-next3-20095` had 13 rows: 6 MOVED, 3 held
   goal-live, and 3 that waited the full 1800 s and ended `NOTMOVED`. Panes 217 and 271 read
   `mid-turn` on **56 of 56** snapshots; pane 301 started as `subagents-in-flight`. Three later
   batches onto next4 had 3 rows waiting, 4 `hold:in-flight`, 2 `hold:goal-live` and 1
   `hold:stale-row` at read time.
3. **27 of the 43 gate rows in §2 protect against hazards that exist only because the process exits
   and relaunches** [E: hand count of the §2 tables]. Those hazards are: the `/exit`
   turn kill, subagents and jobs dying with the process, the exit modal, drafts, the self-exit
   process-group reap, the goal re-drive, the team kill, husk and half-moved and tombstone states,
   kitty, slots and boot capacity, and focus. **Some do not vanish without a restart:** the
   prompt-cache rewrite (the cache is account-scoped), the "owes a turn" nudge after a cap, the rule
   of one actuator per session, two processes on one sid (`duplicate`/`bg-split`), operator intent
   and router admission, and account attribution.
4. **Graveyard.** A zero-restart credential flip was researched in depth on 2026-10-20 (axis 08,
   followed by a 1,688-line design, `impl/C1-credential-flip.md`, with two NEEDS-CHANGES reviews).
   It was **not built**. Its conviction fell 30% → 20% → 15%/14%. Decision packet `745e0fdc78e6` is
   still `open` ("wait for the next wall") [M]. The blockers are:
   - refresh-token rotation, plus an `invalid_grant` that erases the stored item;
   - a leftover `.credentials.json` in next and tertiary (next3), which hides a keychain-only flip;
   - E1 (whether two grants of one account coexist), which was never run;
   - the operator's veto of setup-tokens (ruling `a90e1ac2597e`);
   - whole-directory granularity;
   - account identity keyed on `config_dir` in about 68 files.

   It was designed for **whole-directory cap recovery**, not for per-session voluntary moves.
   **No prior work evaluated a loopback `ANTHROPIC_BASE_URL` bearer-substituting proxy or a
   per-session `CLAUDE_SECURESTORAGE_CONFIG_DIR` lane as a move mechanism.** Axis 08 lists the lane
   only as a future "enabler" (row E). apiKeyHelper and gateway-credential variables were rejected
   three times: they bill the API, not Max, and they disable Remote Control.

---

## 1. The incumbent mechanism, step by step (file:line)

### 1.1 Front doors
- `cc-lr move` → `cmd_move` (`bin/cc-lr:1599`). It parses `--from/--to/--sid(s)/--pane/--until-idle/--wait/--slots/--cold-only/--dry-run`.
  `--abort` writes `<batch>/abort` (`:1624-1630`).
- `cc-lr switch` (self) → `cmd_switch` (`bin/cc-lr:2052`). With the reconciler live, it hands itself
  to the move lane as `wait:self` (`:2135-2142` comment block). Otherwise it runs lr-handoff in the
  foreground and expects to die inside the call: "Claude Code reaps the whole process group of the
  in-flight tool call" (`bin/cc-lr:2215-2220`). The mutex is taken last: "two movers of ONE session
  race a transcript copy against a /exit" (`:2208-2210`).
- `cc-lr switch --sid/--pane/--all-idle` (driver form) → `cmd_switch_driver` (`:959`). It delegates to
  the move lane (design-swap-v3 D1, comment at `:990-995`).
- `cc-lr rotate` (`:1918`, header `:112-135`) is "A FRONT, NOT A THIRD ACTUATOR". Limited sessions go
  to `recover --limited`; the other sessions of a 100% account go to the move lane.
- `cc-lr recover` (`:634`) and `recover --limited` (`:550`) serve limit-errored sessions through the
  reconciler or lr-fleet. The reconciler acts only on a `rate_limit` tail (REPORT §2, `facts.py:12-13`).

### 1.2 Plan (census) — `cl_move_rows` (`bin/cc-lr:1284-1410`)
1. It runs one census: `lr-upgrade.sh --switch-census [--from] --target [--sid…]` (`:1287-1297`).
   Columns are `pane sid account cfg cwd pid disposition`.
2. The census disposition ladder is `lru_switch_census` (`scripts/limit-recover/lr-upgrade.sh:1053-1182`):
   `stale-row` → `on-target` → `self` → `duplicate` → `headless` → `teammate` →
   `lead-with-teammate` → `no-transcript` → `retired-source` → **`mid-turn`** (`!lru_at_rest`,
   `:1097-1100`) → **`subagents-in-flight`** (`:1102`) → **`background-job`** (`:1103`) → composer
   read: `move` | `composer-occupied` | `composer-unknown`/`bg-work-dialog` (`:1104-1108`). The bg
   daemon rows are `bg-session/bg-busy/bg-no-pane/bg-split/bg-attach-*` (`:1115-1160`).
   - `lru_at_rest` (`:263-310`) reads the last 400 transcript lines. It accepts only these as rest:
     `assistant end_turn`, an api-error tail, a stop-hook block-cap record, or a stale
     `<task-notification>` older than 600 s. A trailing `/exit`-style local-command triple and a
     replayed goal record are skipped.
3. cc-lr maps each disposition to `act ∈ move|wait|hold|none` (`bin/cc-lr:1312-1373`). Busy
   dispositions become `wait:<d>` only when `--until-idle S > 0`, and `hold:<d>` otherwise
   (`:1324-1328`).
4. Overlays applied to every move or wait row (`:1375-1404`): `hold:limited`, `hold:api-error-<k>`,
   `hold:in-flight`, `hold:goal-live`, `hold:warm-cache` (with `--cold-only`).
5. Router check: strict and fail-closed (`:1676-1696`). `--dry-run` stops here (`:1684-1693`).

### 1.3 Batch — `scripts/limit-recover/lr-move-batch.sh` (header `:1-27`)
Started detached by the launchd poller (`lrp_move_kick`), never from a tool call. ADMIT runs under
`move-admit.lock`: one router read (fail-closed), a kernel-safety read, per-session claims by
(pid, lstart), and a trust preseed. FAN-OUT starts one worker per row. WATCH writes one census per
`LR_MOVE_SNAP_S` to `snap.tsv` for all waiting workers. CLOSE re-reads the router and runs the prompt
guard against every moved transcript, then writes `summary.json` and one mail.

### 1.4 Worker — `scripts/limit-recover/lr-move-worker.sh` (state list `:6-16`)
| stage | lines | what |
|---|---|---|
| W0 claim | 94-104 | the per-sid claim must name this pid within 30 × 0.5 s, or `claim-lost` |
| intent | 106-146 | `lr_intent_check` at the claim, every 30 s in waits, and before actuate; a shed row is re-authorized |
| W1 fence | 148-154 | `lr_recon_may_act`: the reconciler or a launch-lock holder wins (`reconciler-owns`) |
| W2b limit | 157-210, 261, 445, 487 | a row whose last record became a limit error stops `became-limited` (it owes a turn) |
| **W2 wait** | 212-258 | only `wait:*` rows; it reads the shared `snap.tsv` and breaks on **2 consecutive `move`**; absent twice ⇒ `gone`; budget expiry ⇒ `still-busy:<d>`, and it pages once if the disposition never changed |
| W2d draft | 263-358 | `draft` rows: wait until the box sits unchanged 120 s (or HID idle); junk is cleared with read-back; `[Pasted text #N]` ⇒ `HELD:draft`; real text is carried |
| W2c load | 360-393 | recorded only; not a gate since 2026-10-20 |
| W3 slot | 395-444 | the swap-slot semaphore (width 4), yielding to plan order; 600 s ⇒ `slot-wait` |
| kernel | 446-453 | `lr_capacity_probe_corrected` (swap and headroom) ⇒ `capacity` |
| pre-actuate | 469-508 | re-read the draft; clear a rail `/exit` leftover; final limit read; `hold_focused` for shed plans |
| **W5 actuate** | 509-539 | `lr-handoff.sh --sid --config-dir SRC --cwd --target TO --launch --in-place --source-pane P --voluntary --operator-intent F --no-prompt --no-replace` with env `LR_ADMIT_MODE=swap LR_PLACED_BY=cc-lr-move LR_INPLACE_AWAIT=0 CC_RECYCLE_BGWORK_ANSWER=stop-if-watcher …` (`:514-525`); a clean `HELD:unreachable` gets up to 2 retries after 45 s |
| W6 prove | 541-579 | polls `lr_move_verdict` until it is terminal; MOVED needs the same pid on 2 reads ≥ 5 s apart; bound 300 s (20 s on rc 6) |
| W8 result | 68-86 | atomic `<sid>.json`; claim, fence and slot released |

"NOTHING REFUSES AFTER /exit": every worker hold sits before lr-handoff (`:23-26`).

### 1.5 Actuator — `scripts/limit-recover/lr-handoff.sh --in-place`
1. Audit and salvage bundle, then the **PRECHECK** (`:1272-1290`, run at `:1634`). It calls
   `handoff-fire.sh --probe-recycle-preconditions` (`:1483`) for pane state, composer, registry
   binding, `live_subagents`, team, kitty probe and focus. On a refusal it exits 6 with nothing
   moved. `killed_inflight=<n>` is recorded (`:1520-1545`). With swap mode there is no capacity probe
   and no token (`:331-336`, `:1581`).
2. **Transplant, `--phase admit`** (`:1680-1696`): copy, sha-verify, take the split-brain lock, write
   the tombstone, **and never retire**. Confirm is deferred to handoff-fire, "immediately before it
   writes /exit — which is the only moment the source is provably quiesced" (`:1680-1686`).
3. **Recycle** (`:1966-2030`): `handoff-fire.sh --recycle --transplanted-source --resume-launcher L
   --resume-cfg TCFG --transplant-cause voluntary --source-pane P --source-session S`.
   `--transplant-cause` re-enables the subagent gate for a voluntary move (`:1974-1985`).
4. handoff-fire `recycle_fire_armed` (`scripts/handoff-fire.sh:20756-20765`): the watcher starts
   FIRST (detached, heartbeat-verified) and `/exit` is typed LAST. The watcher waits for the shell and
   types `bash <launcher>`, which runs `lr-fire-resume --no-prompt` → `claude --resume <uuid>` under
   the target config dir. Gates on this path: `hf_bg_work_gate` (`:3462-3500`), composer and draft
   carry (`:20740-20755`), team (`:14473-14475`), kitty (`:14551-14556`), launch-lock and holder
   (`:14166-14217`), focus (`:3839-3849`).
5. Custody phases on failure (`lr-transplant.sh:27-31`): `unconfirm` restores `<sid>.jsonl` from
   `.handed-off` when the source never exited; `fold-stub` handles a stub that reappeared; `abort`
   gives up an unconfirmed move.

### 1.6 Transplant — `scripts/limit-recover/lr-transplant.sh`
- It copies `<slug>/<sid>.jsonl` and `<slug>/<sid>/` (subagents, workflows, journals) (`:11-12`).
- The split-brain lock is `~/.reso/limit-recover/locks/<sid>.lock`, recording `{owner, chain[], ts_first}` (`:13-17`, `:161-172`).
- The tombstone `<sid>.HANDOFF.json` is written beside the source. The source is renamed to
  `.jsonl.handed-off` only on confirm. Every rename is link-then-unlink (`:32`).
- It **refuses when source and target share one physical `projects/`** (`:138-142`).
  Measured symlink layout [M, `python3 -I` os.readlink over 5 dirs]:
  - `~/.claude-next/{projects,sessions,history.jsonl,shell-snapshots,session-env,file-history,…}` → `~/.claude/…`, so next and `~/.claude` are one store;
  - secondary, tertiary and quaternary each have a **real** `projects/` and `sessions/`, and only `todos, tasks, settings.json, plugins, hooks, scripts, CLAUDE.md` are symlinked;
  - `.credentials.json` exists as a file only in `~/.claude-tertiary` (presence checked; content not read). Axis 08's skeptic also recorded one in `~/.claude-next` on 2026-10-20; my check reported `absent` there tonight [M].

### 1.7 Verdict — `lr_move_verdict` (`scripts/limit-recover/lr-move-lib.sh:121-225`)
Conjuncts P1-P7 are file and process facts, never prose (`:14-19`, `:110-120`):
- P1: the registry row's pid is the live one (lstart);
- **P2: the process env `CLAUDE_CONFIG_DIR` equals the target**;
- **P3: exactly one live transcript, under the target store**;
- P4: no foreign tombstone;
- **P5: exactly one live holder**;
- P6: admitted with the target ranked;
- P7: no open resume debt.

**A no-restart account change fails P2 and P3 by definition.** The process keeps its config dir and
its transcript stays in the source store. Any replacement must redefine "on account X".

---

## 2. Every wait:/hold: gate, the hazard it prevents, and whether it is restart-intrinsic

Key: **V** = the hazard vanishes if the process never exits or relaunches. **A** = intrinsic to
changing the billing account by any mechanism. **G** = a general concurrency, identity or
authorization rule that survives any design. **P** = partly.

### 2.1 Census dispositions (bin/cc-lr:1312-1404; lr-upgrade.sh:1053-1182)
| gate | hazard it prevents (cited) | class |
|---|---|---|
| `wait/hold:mid-turn` | `/exit` "INTERRUPTS the in-flight turn and exits within seconds (E2E 2026-07-03 — twice: the busy turn died with no output persisted; /exit does NOT enqueue-to-turn-end the way /clear does)" (`handoff-fire.sh:20757-20759`). Also A03 M1: the admit copy goes stale while a healthy source appends, a "Silent truncation of the tail" (`A03-precheck-healthy-source.md:17`) | **V**. With no exit and no copy there is nothing to kill or truncate. Residual: a request already in flight finishes on the old token (open question) |
| `wait/hold:subagents-in-flight` | the recycle kills in-flight subagents (`lr-handoff.sh:1520-1545`, "exactly the in-flight units the recycle is about to kill"); A03 M2 / A04 I4 "A voluntary move may not destroy in-flight work" | **V**. Subagents are in-process; their requests build their own clients (open question: does every subagent request run the change check) |
| `wait/hold:background-job` | Bash-tool jobs die with the exit; a ship-land killed between rebase and push is "the worst single loss" (`handoff-fire.sh:3434-3443`; `A03:73`). Watcher shells (`cc-await-ping`) are not work (`lr-upgrade.sh:540-548`) | **V** |
| `hold:bg-work-dialog` | the exit-time "Background work is running" modal; nothing may answer it ("Exit and stop tasks" ends the only copy's work); pane 350 sat through 3 × 3600 s waits (`bin/cc-lr:1352-1357`; `lr-upgrade.sh:629-643`) | **V**. The modal is raised by `/exit` |
| `wait/hold:composer-unknown` | the box cannot be read (a modal); a keystroke would be consumed as the modal's answer (`A03:93`, citing handoff-fire `:2700-2710`) | **V** |
| `draft` / `hold:draft` | `/exit` typed into a draft "would MERGE with it into one message" (`handoff-fire.sh:20750`); a `[Pasted text #N]` lives only in session memory and clearing it destroys it (`lr-move-worker.sh:352-353`); a leftover `/exit` was retyped into a successor (pane 384, `:292-295`) | **V** |
| `wait:self` / `hold:self` | the caller cannot exit itself mid-tool-call (process-group reap, `bin/cc-lr:2215-2220`); the R4/R5 loop left a self-mover no lane (`:1358-1371`) | **V** |
| `hold:goal-live` | "a /goal is driving turns; its goal would drive it on mid-move"; a live goal re-drives at every Stop, so the session "never rests" (`bin/cc-lr:1389-1400`, `:1220-1234`); "armed /goal dies with the process" (A10 #4) | **V**. In-process, the goal keeps running across the switch |
| `hold:warm-cache` (`--cold-only`) | a warm move rewrites the prompt cache on the next turn (`bin/cc-lr:1308-1310`) | **A**. "Prompt cache: account-scoped" (`08-zero-restart.md:189-191`; A10 #2); 273K-479K tokens of cache writes measured after moves [C, REPORT R11] |
| `hold:limited` | it owes a turn the no-prompt lane does not type, so it would land at rest, unanswered, and read MOVED (`lr-move-worker.sh:157-162`; `bin/cc-lr:1383-1384`) | **P/A**. A capped turn *ends* (axis 08 skeptic S3), so any design must still start a new turn (a nudge) |
| `hold:api-error-<kind>` | not a healthy idle session (`bin/cc-lr:1385-1386`) | **G** (diagnostic) |
| `hold:in-flight` | another actuator holds the claim; "two actuators on one session" (`lr-move-worker.sh:460-466`; `lr-handoff.sh:1329-1334`, 2026-10-18) | **G** |
| `hold:being-recovered` | the same command already recovers it (`bin/cc-lr:1374`) | **G** |
| `hold:husk` | a forward husk: moved off its account with nothing running it (`bin/cc-lr:1339-1343`, 186452ed, 2026-10-10) | **V** as a new hazard. Husks are products of transplant plus exit |
| `hold:half-moved` | the exit was cancelled after the source was retired; a stub re-created `<sid>.jsonl` (`bin/cc-lr:1268-1280, 1344-1347`, c56c729c, 2026-10-13) | **V** |
| `hold:retired-source` | a stale handoff tombstone blocks every prompt (`bin/cc-lr:1348-1349`; `lr-transplant.sh:321-333`, 762a6daa, 8e18da3f) | **V** |
| `hold:teammate`, `hold:lead-with-teammate` | "every graceful lead exit runs cleanupSessionTeams, which kills the members" (`lr-upgrade.sh:816-819`, `:406`) | **V** for the kill. But each teammate is its own process with its own credential source, so a per-process mechanism must cover members too |
| `hold:duplicate` | two live holders of one sid, already a split brain (`lr-upgrade.sh:1088`; A03:74) | **G** |
| `hold:bg-split` | "the SAME conversation is also live as an interactive session — two writers already; never move either copy" (`lr-upgrade.sh:1116-1119, 1155`) | **G** |
| `hold:bg-session` / `bg-busy` / `bg-no-pane` / `bg-attach-*` | `--bg` daemon sessions: no pane to relaunch in, and keys would land in another claude (`lr-upgrade.sh:1115-1160`) | **P**. Pane problems are V. A daemon-hosted session is still a separate process whose credential path must be covered |
| `hold:stale-row` | the registry row is not live (`lr-upgrade.sh:1083`) | **G** |
| `hold:headless` | a headless process has no pane to relaunch into | **V** (nothing to relaunch); its credential still has to move |
| `hold:no-transcript` | no transcript found, so nothing to transplant | **V** mostly |
| `hold:<other>` default | anything unmapped is held (`bin/cc-lr:1372`) | fail-closed rule, **G** |

### 2.2 Worker and actuator holds (lr-move-worker.sh; lr-handoff.sh; handoff-fire.sh)
| gate | hazard | class |
|---|---|---|
| `claim-lost` (W0) | two workers on one sid (`:94-103`) | **G** |
| `intent-invalid` / `shed-revoked` | a lapsed or revoked authorization still actuating (`:106-146`; batch 69593 held 4 slots 107-116 s, then refused) | **G** |
| `reconciler-owns` (W1) | two dispatchers on one session (`:148-153`) | **G** |
| `still-busy:<d>` / `gone` (W2) | waiting past the budget for an idle that never comes (`:212-258`) | **V**. It is the idle wait itself |
| `became-limited` (W2b) | moving an owing session with no prompt (`:157-210`) | **P** (see `hold:limited`) |
| `HELD:draft` (W2d) | destroying or merging a draft (`:263-358`) | **V** |
| `HELD:load` (former W2c; handoff-fire on a typed relaunch) | boots under load; F1 strand pane 44, 2026-10-09 (`:360-371`) | **V** |
| `slot-wait` (W3) | more than 4 concurrent kitty RPC streams or overlapping TUI boots (`lr-move-lib.sh:227-237`) | **V** |
| `capacity` | swap ceiling and headroom for a boot (`lr-move-worker.sh:446-453`) | **V** |
| `HELD:focused` / `focus-unknown` | keys typed into a pane the operator is using (`:488-508`; `handoff-fire.sh:3839-3849`) | **V** |
| `HELD:unreachable` / `HELD:wedged` / `HELD:pane:resolver-unavailable` | a deaf or stuck kitty control socket (`:457-467`; `handoff-fire.sh:14551-14556`) | **V** |
| `HELD:no-shell` | a launcher-rooted pane, where `/exit` closes the window (`lr-handoff.sh:1509-1514`) | **V** |
| `HELD:mid-turn` / `HELD:busy` (`hf_bg_work_gate`) | the last re-read of at-rest before `/exit` (`handoff-fire.sh:3462-3482`) | **V** |
| `HELD:bg-work:ship-land/other` | killing a land or a job (`handoff-fire.sh:3484-3497`) | **V** |
| `HELD:team` | orphaning live members (`handoff-fire.sh:14473-14475`) | **V** |
| `HELD:launch-lock` / `HELD:holder` | a foreign live launcher, or no live holder of the sid (`handoff-fire.sh:14166-14217`) | **G** |
| precheck `REFUSED:*` (rc 6) | the ordering defect: a transplant that then cannot recycle leaves a husk (`lr-handoff.sh:1272-1276`) | **V** |
| transplant `stub-beside-retired`, `lock-mismatch`, `target-held`, split-brain | two targets or owners for one uuid (`lr-transplant.sh:34-43, 839-853`) | **G** in spirit (one owner); the file mechanics are **V** |
| W6 `FAILED` / `STRANDED` | the relaunch dies at boot, or two live copies remain (`lr-move-lib.sh:110-120`) | **V** as a class. A no-restart design needs its own proof of the account switch |

Tally [E: hand count of the rows above]: of 43 rows (24 census rows and 19 worker or actuator rows),
27 are V, 12 are G and 4 are A or P.

---

## 3. Documented casualty classes of past moves (counts as cited)

| class | count / instance | source |
|---|---|---|
| **All move-lane outcomes** | 83 batches 2026-10-06 → 10-24: 47 MOVED, 220 NOTMOVED, 13 FAILED, 12 STRANDED. NOTMOVED split: 72 HELD, 63 still-busy, 22 aborted, 17 REFUSED, 15 batch, 14 slot-wait, 13 claim-held. Since 10-19, 8/8 MOVED | [C] `account-rotation-100p-2026-10-24/REPORT.md:101,354-355`; evidence.json move-mechanics |
| **Forks (two live copies)** | 13 FAILED before 10-19, "two live copies of the session"; 12 classed `FAILED source-ambiguous` | [C] evidence.json move-mechanics facts |
| Fork, bg daemon | `SPLIT-BRAIN: live on $target … the $from daemon re-claimed job` | [R] `lr-upgrade.sh:1878` |
| Custody erased | a lock-gone second hop writes a fresh lock and "the A hop is erased from custody" | [R] `A04-transplant-rails.md:195` |
| **Stranded (no process holds the session)** | 12 before 10-19; 9f6593c5 STRANDED 2026-10-17 reached no summary; the nohup watcher died twice on 2026-07-13 ("0-byte log, no relaunch, stranded pane"); the F1 strand at pane 44, 2026-10-09 | [C] REPORT R10; [R] `lr-move-worker.sh:80-81`; `handoff-fire.sh:20760-20763`; `lr-move-worker.sh:369` |
| **Husks** | forward husk 186452ed (2026-10-10); the husk generator reproduced A/B in LIMIT_RECOVER_100P (A03 C13); W5b canary 3 had **181 husk spawns**, every one held | [R] `bin/cc-lr:1339-1341`; `A03:61`; `handoff-fire.sh:4353` |
| **Half-moved** | c56c729c, 2026-10-13: the exit was cancelled after the retire | [R] `bin/cc-lr:1345-1347` |
| **Stale tombstones blocking prompts** | 762a6daa and 8e18da3f measured live, "all four live cases"; 762a6daa was reported SWITCHED while it could not take a prompt; the return hop pane 14 / 4d059264, 2026-10-11 | [R] `lr-transplant.sh:321-333, 366-370`; `lr-move-lib.sh:14-19` |
| **Lost turns** | `/exit` killed a busy turn with no output persisted, twice in E2E (2026-07-03); A03 M1 silent tail truncation (uncounted; "no consumer anywhere would notice") | [R] `handoff-fire.sh:20757-20759`; `A03:17` |
| **Never-moved busy sessions** | 63 still-busy NOTMOVED rows; 2a707a01 read mid-turn 151 times over 3600 s; **tonight 15f652bd (pane 217) and 502bd860 (pane 271) read mid-turn on 56/56 snapshots over 1800 s**, and 88fc8283 (pane 301) started subagents-in-flight; pane 350 waited 3 × 3600 s at a modal | [C] REPORT R10/R12; [M] events.jsonl read (§6 cmd 14); [R] `bin/cc-lr:1353-1354` |
| **Drafts** | pane 384, 2026-10-18: a rail `/exit` was retyped into the successor; a pasted block cannot be carried; `/exit` plus a draft merge into one message | [R] `lr-move-worker.sh:292-295, 352-353`; `handoff-fire.sh:20750` |
| **Goal loss or goal hold** | 3e929a81 held 19.5 h on an armed but idle goal; pane 297 (2026-10-13) was held on a rejected account; goal-arm abstain happened twice (once on 624e04a1); "armed /goal dies with the process"; tonight 3 + 1 `hold:goal-live` rows | [R] `bin/cc-lr:1220-1222, 1389-1392`; `NONLIMIT_RESUME_LADDER.md` §4 (~:731-748); A10 #4; [M] plan.json |
| **Subagents killed** | `killed_inflight` was never written, so ingest clause A6 failed 68 of 68 bundles (the kills were unaudited) | [R] `lr-handoff.sh:1520-1527` |
| **Team kills** | a lead's graceful exit kills its members (structural; not counted) | [R] `lr-upgrade.sh:816-819` |
| **Cache cost** | the first turn after a warm move wrote 344,023 / 397,875 / 479,138 / 273,235 cache tokens and read about 12.8K; estimated +1.9× context; A12: transplant cost 0.109 pp median, 0.315 pp max | [C] REPORT R11; evidence.json; `A12-premise-empirics.md:15` |
| **Outage per move** | 58-129 s (6 moves on 10-24); actuate→proof p50 207 s, p90 823 s, max 1396 s (n=47) | [C] REPORT R10; evidence.json |
| **Drain-era cost (predecessor)** | 376K input-equivalent tokens per subject turn at the median; pane 222 quoted a 23 h-old reply as a decline; 98aae987 a false NOTMOVED | [R] `lr-move-worker.sh:18-21`; `lr-move-lib.sh:14-19` |
| **Lane overhead** | 2026-09-23: five attempts and ~8 h to move two panes; batch 69593: 4 rows held all 4 slots 107-116 s, then intent-invalid; the old load wait held 4/4 rows 605-613 s, and two idle sessions turned limited while waiting; 2026-10-17: five parallel one-sid batches, ~550 s of router reads, two refused | [R] `lr-upgrade.sh:802-804`; `lr-move-worker.sh:107-110, 360-363`; `bin/cc-lr:1236-1240` |
| **Recovery latency** | reconciler detection→ENGAGED median 81 min (n=19); the 2026-10-20 incident took 1 h 43 m to recover 5 of 9 | [C] REPORT R21; `08-zero-restart.md:292-294` |
| **Dispatch identity** | a transplanted or resumed pane has no `ITERM_SESSION_ID` and no registry row, so every handoff-fire aborts at F3 | [R] `.claude/rules/agent-operating-lessons-situational.md` (transplanted-session-loses-dispatch-identity) |

---

## 4. Branch graveyard: prior credential, proxy and mid-turn attempts

### 4.1 Commands as briefed
- `timeout 60 git -C <wt> log --all --oneline -i --grep='apiKeyHelper\|proxy\|credential\|keychain\|BASE_URL\|token swap\|mid-turn' | head -80` [M]
  returned **955 lines in total** (`| wc -l`). The first 80 are mostly unrelated duplicates across
  branches (cc-decide, capacity-admit, ms365 proxy, research-kit). The relevant ones:
  - `4948721bc`/`582b304d3`/`56f5900f0` "a self-recycle run mid-turn waits for its turn to end instead of refusing". The incumbent's answer to mid-turn was to **wait**.
  - `eead72134` "a SELF swap does not count its own mid-turn session against the active ceiling".
  - `3f923cfbf`/`276546694` "claude-accounts: read .credentials.json read-only when the keychain item is missing".
  - `186d5155e` cc-relogin k==0.
  - `819b3342b` "recycle SIGTERM proof — at rest on 2.1.293 a pinned SIGTERM exits like /exit on five of six assertions".
  - `13077919e` ms365 proxy launcher (an MCP proxy, unrelated).
- `timeout 60 git -C <wt> log --all --oneline --diff-filter=A -- '*proxy*' '*apikey*' '*credential*' | head -40` [M]
  returned 8 lines:
  - `dc13d1a09`/`335940ec0` added `docs/research/lr-sustained-load-2026-10-20/impl/C1-credential-flip.md` (1,688 lines);
  - `13077919e`/`0ddf94b64`/`555b504d4` added `scripts/mcp-ms365-proxy.sh` (unrelated);
  - `9327ddabe`/`f5fbae9f0`/`22a2b159f` added the lesson `zero-limit-credential-cannot-measure-free.md` (unrelated).
  **No code file implementing a credential swap or proxy was ever added** [M].
- A narrower grep, `--grep='apiKeyHelper\|BASE_URL\|OAUTH_TOKEN\|oauth\|token swap\|hot.swap\|live.swap\|swap.*credential\|credential.*swap\|relogin\|keychain'` [M], found the relogin research line (2026-07-25 → 08-07), `dd02f7df0`/`9737a84c5` (setup-token "Method A is dead": 403 at the usage endpoint) and `002da6792` ("unattended re-auth executor + token de-sharing").
- A grep over `zero-restart|credential flip|grant bank|de-shar|claude-swap|SECURESTORAGE` [M] found only `abb17fa10` (the shed), `002da6792` and the sustained-load docs. **There is no implementation commit for a flip.**

### 4.2 Tree grep (bin scripts hooks docs lib) [M]
File counts: `apiKeyHelper` 17 · `ANTHROPIC_BASE_URL` 24 · `CLAUDE_CODE_OAUTH_TOKEN` 18 ·
`CLAUDE_CODE_OAUTH_401_WAIT_MS` 1 · `ANTHROPIC_AUTH_TOKEN` 10 · `probeCredentials` 1 ·
`Claude Code-credentials` 25. Code hits: `bin/claude-kimi` (`ANTHROPIC_BASE_URL` to another
provider, not an account switch), `bin/cc-config-slot` and `scripts/relogin-desharing-activate.sh`
(de-sharing), and `bin/claude-accounts`/`bin/cc-relogin` (keychain heal and relogin).

### 4.3 Each prior attempt and why it stopped
| # | attempt | date / where | what it found | why it stopped |
|---|---|---|---|---|
| G1 | **Zero-restart credential flip (axis 08)** | 2026-10-20, `docs/research/lr-sustained-load-2026-10-20/08-zero-restart.md` (commit `7b68849b4`) | Mechanically yes: `j7`→`Pl`→`wA` on **every client build** (skeptic S2); 30 s storage cache; the 401 path `y$` adopts the stored token; the refresh race adopts it; a sibling-login watcher exists (`:20-26, 115-148, 431-438`) | Rotation plus the `invalid_grant` erase (`:31-37`); a leftover `.credentials.json` makes a keychain flip invisible (S1, `:406-429`); E1 unrun; whole-dir granularity; RC bridge account binding (`:182-185`); "Recommendation: do not build a flip yet" (`:53-58`) |
| G2 | **C1 credential-flip design B′** (one spare grant per account, move semantics) | 2026-10-20, `impl/C1-credential-flip.md` (commit `dc13d1a09`) | three-lock protocol (`.oauth_refresh.lock`, legacy `<realpath>.lock`, `.storage-write.lock`); the write shape is `security -i … -X hex -a $USER`; RFC 9700 family revoke risk; the rail would un-cap X (`:36-107, 108-140`) | **OPERATOR** verdict, Gate 0 first; conviction 20% → 15% (efficacy review) → **14%** (safety review: 17 required changes) (`:36-48, 888-923, 1318-1334, 1666-1688`). Setup-token (design C) blocked by operator ruling `a90e1ac2597e` (`:50-56`). Each spare grant costs about one interactive login per 27.7 days; unattended relogin proved 3/106 (`:57-68`). Packet `745e0fdc78e6` is **open** [M] |
| G3 | Credential swap or scripted `/login` (q3a) | 2026-10-06, `limit-recover-zero-memory-2026-10-06/slots/q3a-product-permits.md:11-15, 74` | `/login` switches the live session but moves the whole dir and needs a browser and pane I/O; an outside swap is "UNSUPPORTED (no documented contract)"; changing `CLAUDE_CONFIG_DIR` live is NOT PERMITTED | synthesis `:73` "Not to do … build rotation on a credential swap or scripted `/login` (85, q3a)" |
| G4 | Keychain blob injection; apiKeyHelper | 2026-07-25, `autonomous-relogin-methods-2026-07-25.md:233-234` | G: "Direct keychain/.credentials.json blob injection … Rejected — community hack … a bad write = logout"; H: "`ANTHROPIC_API_KEY` / `apiKeyHelper` … **Inapplicable** — bills API credits, not Max quota" | rejected |
| G5 | Gateway / BASE_URL | 2026-09-17, `union-alpha-drain-2026-09-17/A9-throughput.md:174-180`, `A3-drivability.md:134-142, 222` | "Setting only `ANTHROPIC_BASE_URL`, without a gateway credential, doesn't replace the subscription … gateways must forward the OAuth capability in `anthropic-beta`"; any gateway credential variable "replaces the subscription" (a money trap) | it was about third-party gateways and other models. **A local bearer-substituting proxy for account moves was never evaluated** |
| G6 | Token de-sharing (per-session-class `CLAUDE_CONFIG_DIR` slots) | 2026-07-25 design, `bin/cc-config-slot`, `scripts/relogin-desharing-activate.sh:1-30` | per-class config-dir isolation | gated on E1 = Variant A and a proven renewal; operator-only; never activated |
| G7 | Setup-token / env token ("Method A") | `setup-token-scope-refutation-2026-09-08.md`; commits `9737a84c5`, `dd02f7df0` | inference-only scope, 403 at `/api/oauth/usage`, no RC or connectors; env token is kept for the whole session (`Pfs`), FD token cached once (`eM`) | operator ruling `a90e1ac2597e` (2026-09-08, `48b46f513`): "drop long-lived setup-tokens entirely" |
| G8 | Forced-relogin root cause | 2026-08-02, `forced-relogin-rootcause-2026-08-02.md:45-50, 88-96, 280-300` | refresh tokens rotate; `invalid_grant` erases the item; `next`, with multiple grants, is the strongest correlate of forced re-logins (next4, one grant, 0 in 30 days) | it bounds every design that puts a grant in more than one item |

### 4.4 Re-confirmed in the extracted 2.1.293 source [M, `python3 -I` regex over `/tmp/mtam/cc293-src.js`]
- `CLAUDE_SECURESTORAGE_CONFIG_DIR`: 10 hits. `uw()`, `FF()` and `cPt=30000` are at byte offset
  **3737500-3738160**: `function uw(){let e=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR;…}` and
  `` `Claude Code${cn().OAUTH_FILE_SUFFIX}${e}${c}` `` with `c = -sha256(dir)[:8]`.
- `tengu_oauth_401_recovered_from_keychain` @4663853; `tengu_oauth_token_refresh_race_resolved` @4669209, 4670941; `oauth_refresh.lock` @4045892, 4665771, 23639737; `storage-write` @3741545.

So the per-process credential-store selector exists and is env-read. It cannot re-point a live
process. A per-session lane therefore needs **one** launch under the lane before any later
zero-restart move.

---

## 5. Candidate invariants any replacement must keep

1. **One writer per session uuid at every instant: no transcript fork.** Enforced today by the
   split-brain lock (`lr-transplant.sh:921`, `:839-853`), verdict P5 (`lr-move-lib.sh`), and the
   `duplicate`/`bg-split` holds; A04 I1. A no-restart design keeps the one process and must never
   start a second.
2. **No in-flight work destroyed** (A04 I4): turns, subagents, background jobs, lands, team members
   and drafts. In the incumbent this is the whole reason for the `wait:` gates.
3. **No silent truncation; continuity content-verified.** The incumbent sha-verifies its copies
   (admit and confirm). A replacement must prove the conversation continued on the same bytes. With
   no copy that proof is trivial, but it must be *stated* and checked.
4. **The verdict comes from disk and process facts, never prose, and can be re-derived at any time**
   (`lr-move-lib.sh:14-19`; `cc-lr move --status`). The new proof must say "billed to Y" from a
   measured fact: response headers, the usage feed, or the store hash. "process env names Y's dir"
   is P2 and becomes meaningless.
5. **Absence is loud.** Absent is not empty: the two-snapshot `gone` rule (`lr-move-worker.sh:212-218`),
   the LOUD missing `killed_inflight` (`lr-handoff.sh:1540-1544`), and the page when a wait never
   changed (`:242-252`). An unreadable store, lane or attribution must be its own verdict, never a
   silent default.
6. **Every refusal happens before the point of no return. Nothing refuses after the irreversible
   step** (`lr-move-worker.sh:23-26`; design-swap-v3 I8, `lr-handoff.sh:331-336`). For a credential
   write: journal first, then make it atomic or reversible (C1 §2.2 write-ahead journal).
7. **One actuator per session**, claimed by (pid, lstart) and released on every path
   (`bin/cc-lr:2208-2210`; W0/W8).
8. **Credential safety.** A grant lives in exactly one item at a time; nothing ever provokes the
   `invalid_grant` erase; all of Claude Code's locks are taken in its order; heal and relogin are
   fenced off moved stores; no token is ever printed (C1 §1 consequences (a)-(e), §2.2).
9. **One time-aware account-attribution source of truth** ("session S is billed to account A from
   time t"). It is consumed by the router, the reconciler's facts (else X is un-capped, C1 finding
   5), the usage sweep and the verdict (C1 R.4 #2). About 68 files key on `config_dir` [C, axis 08
   L4].
10. **Bounded external calls under load 300-900.** Every wait has a budget, no unbounded `ps -ax`,
    and timeouts are sized (planners hang at 60 s: REPORT R14). No step may depend on kitty's
    control socket if it can avoid it.
11. **Operator authority.** Intent is re-checked at every hold, the router admits fail-closed,
    narrow-first kill switches exist (`LR_MOVE_LANE=off`, …), and no turn is ever typed into a
    session that is not owned.
12. **No filler sessions.** Never launch a session to burn quota (vetoed decision 8f9618059700,
    REPORT §7).
13. **Teams are never orphaned**, and a teammate's account follows its lead's policy.
14. **Fail closed on binary drift.** Every anchor into the minified binary is pinned to the
    installed version and refuses on an uncertified binary (C1 Gate 5, R11).

---

## 6. Commands I ran (all read-only) with key output

1. `wc -l` of the 8 named files → cc-lr 3295, lr-move-worker 579, lr-move-lib 465, lr-handoff 2464, lr-transplant 1176, lr-move-batch 380, REPORT 389, ladder 934.
2. `cat .claude/rules/*.md | grep -n -i 'move|transcript|fork|…'`: lessons on transplanted dispatch identity, engaged ≠ running, a lead that cannot exit unattended, a dead-session verdict.
3. `cat -n lr-move-worker.sh` (full); `sed -n 1185,1420p bin/cc-lr` (census); `grep -n` for the function index.
4. `grep/sed` over `lr-upgrade.sh` for the disposition ladder (`:263-310`, `:1053-1182`, `:540-548`, `:629-643`).
5. `sed` over `lr-handoff.sh` (`:1-110`, `:1272-1290`, `:1520-1545`, `:1670-1700`, `:1966-2030`); `lr-transplant.sh` header and the `FROM_PROJ_REAL` refusal (`:138-142`).
6. `python3 -I` os.readlink over 5 config dirs → the symlink layout in §1.6.
7. `sed /^lr_move_verdict/,/^}/` → P1-P7.
8. Read REPORT.md in full; `python3 -I` walk of evidence.json → found[move-mechanics] facts (outcome counts, cache, holds).
9. `grep/sed` over A03, A04, A10, A12 and the NONLIMIT_RESUME_LADDER sections.
10. `grep -o 'HELD:…' handoff-fire.sh | uniq -c` → unreachable 5, load 5, focused 4, draft 4, busy 4, team 3, mid-turn 3, launch-lock 3, holder 3, wedged 2, …; `sed :3380-3500` (bg gate), `:20750-20765` (/exit interrupt).
11. Both briefed git commands (§4.1), plus the narrower greps.
12. The tree grep (§4.2); read 08-zero-restart.md in full; `grep -E '^#'` and sections of C1-credential-flip.md.
13. `python3 -I` over `~/.claude/autonomy/decisions/745e0fdc78e6.json` → `open`; `bd40ec7f3d4f`, `156c1aa935e7` → no decision file (they are queue or step rows, not packets).
14. `python3 -I` over `~/.reso/limit-recover/move/20261025*` plan.json and result json → 4 batches (§0.2). Events for the 3 NOTMOVED rows → `56 snapshot(s) read, first 'mid-turn'` ×2, and `first 'subagents-in-flight', changed`.
15. `python3 -I` regex over `/tmp/mtam/cc293-src.js` → offsets in §4.4.
