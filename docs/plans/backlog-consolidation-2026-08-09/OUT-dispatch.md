# cluster C (dispatch / backlog / premise / desk / autonomy loop) — triage vs origin/main @ 51bdb524720aeb6c2fd49d14c1c584dce1456650

Measured 2026-08-09. **Read note that changes how you read everything below:** the shared checkout
`~/Development/claude-infrastructure` sat at `c2ccbeb8`, **19 commits behind `origin/main`**, for the
whole session. Every load-bearing claim in this file was therefore re-verified with
`git show origin/main:<path>`, not with a working-tree read. (This is itself an instance of item
`500765da985c` / `a3feeba64fe7` — a triage run against a behind-checkout would have KEPT items that
trunk had already fixed, and PRUNEd nothing that trunk had gained.)

## Summary

counts: **PRUNE 6 / UPDATE 7 / KEEP 43 / MERGE 9** = 65

The single most consequential thing measured: **`bin/cc-premise` already exists and is already wired
into both consumption points** — claim guard (5) in `bin/cc-backlog:1149` and the worker-brief
premise contract in `bin/cc-dispatch:1262-1266` (landed `e4f73cb7`, 2026-08-07; CONCURRENCY_PROGRAM
§S3 is marked LANDED). The lead's premise for this slice is correct but the starting point is one
step further along than assumed: the gate exists, fails open, refuses 12 of 359, and advises 78. What
does **not** exist on trunk is the *derived-read* layer — no falsifier, no cluster-as-unit, no
ranking. `git grep falsifier origin/main -- bin` returns 3 hits, none in `cc-premise`.

## Verdicts

### PRUNE (6)

```
95422d3518bc | PRUNE | 437ccc0b "feat(cc-notify): route the cloud send to the session's owning account" (08-08 03:58) names this id in its body: "Closes the gap the sibling desk measured (backlog 95422d3518bc)". Consequences (1)(2) shipped — `bin/cc-cloud:394` takes `--account`, persists it (`:436`), emits it in JSON (`:672`), and the routing comment at `:390` restates the A/B verbatim.
e820dbfde7d2 | PRUNE | The prescribed script does not exist in either store: not in live `~/.claude/autonomy/pending-activation/` (31-* is absent) and not on trunk (`docs/activation/pending-activation/31-*` = `31-compressor-sentinel-activate.sh`). Its premise is also gone: `~/.claude/cc-roles/` now holds exactly one file, `orchestrator`, and it is **0 bytes** — there are no iTerm2 UUIDs left to normalise. The live concern (no resolvable desk role) survives in 08ba1e3dccc2.
fdf4161aeb28 | PRUNE | `git ls-tree origin/main docs/activation/pending-activation/` lists `05-ship-rail-push-allow-activate.sh`. The repo copy exists; the loss-exposure this item names is closed.
ef73328d0c8b | PRUNE | Same read: BOTH named scripts are on trunk — `05-ship-rail-push-allow-activate.sh` and `13-mailbox-gc-activate.sh`. Live-only status refuted for both.
d46bb5fbdb8f | PRUNE | The recurrence guard was BUILT. `hooks/activation-watch.sh` carries `MIRROR_REL="docs/activation/pending-activation"` (:55), a `parity_axis()` (:346) that reports live-only / repo-only / content-drift / `.local`-exempt, a standalone `--parity` entry (:583) with "rc 1 on ANY drift (incl. an unresolvable mirror)", and a `--selftest` axis 2 covering all six states (:533-564). It also honours lookup-miss-is-not-absence: an unresolvable mirror is REPORTED, never silently skipped (:350).
97148f9ea7e2 | PRUNE | The sanctioned mechanism this item proposes already shipped as `scripts/esc-exempt.manifest` (landed `bf5f8519`, 2026-08-02), read from the BASE revision so an entry cannot exempt the land that adds it. `git show origin/main:scripts/esc-exempt.manifest` declares `hooks/session-index-*.sh` and `hooks/lib/session-index-*.sh` — the exact retention-lane files. The manifest's own header records the same 4 parks this item re-measured.
```

### UPDATE (7)

```
5deb4418a648 | UPDATE | Core is live — but its own diagnosis and remedy are both refuted by later siblings and must be rewritten before dispatch. (a) "the dispatcher skips the claim read at fire time" is FALSE: `bin/cc-dispatch` step 5a claims BEFORE it fires (header :32, claim site :1088 "THE ACTUATOR IS THE ARBITER, for four distinct predicates"). (b) Its proposed fix — "gate the FIRE on the same lease the worker would take" — is refuted by f61c1eaaba05: at fire time the lease legitimately answers "incumbent dead", because the lease identity is a dispatch-time SHELL pid. What survives: a duplicate arrives, orients, and never touches the gate that would refuse it. Should now say: the lease key must outlive the work (worktree or dispatch-issued lease id), and the brief must claim-or-stand-down as action 1.
f61c1eaaba05 | UPDATE | Premise verified in shape, stale in citation. `git show origin/main:bin/cc-backlog` still names `<host>-<pid>` a SHELL not the work (:268) and `claimer_live` is still the oracle at :950/:1028/:1233. But two commits landed on this exact surface after the measurement: `1cdd2c37` "the claim lease displaced a LIVE worker — one oracle, not two" and `5d6cb758` "a dispatcher's claim is a hand-over, not a steal" (08-09 15:11), and `:387` now states the consequence explicitly — "`claimer_live` is false BY CONSTRUCTION for every dispatched item and Rule A degrades to an [advisory]". Re-read `:380-435` before rebuilding; the item's cited line (~1180) has moved.
d6d8b259235d | UPDATE | The bare-reopen half LANDED: `59424bed` "feat(cc-backlog): a dispatcher self-release is not a worker thrashing" + `6d6c5c95` "fix(cc-dispatch): the rollback now says WHY it released the claim" (both 08-07 10:17), and `1c3e8e9f` (08-08) closed a fourth rc-4 cause that was journalling a correct refusal as a lease failure. The UNBLOCK half is untouched and is the live remainder — trunk still folds `unblock → "open"` unconditionally (`bin/cc-backlog:681`) with no re-read of the block reason. Its "UNPROVEN HYPOTHESIS" (spawn produced a live worker while cc-dispatch judged it failed) is still unmeasured and must not be carried as established.
3c6bf04ba842 | UPDATE | Step (1) of its own SAFER SEQUENCE has landed: `scripts/handoff-fire.sh` now bounds every it2 IPC — `HF_TIMEOUT_S="${HANDOFF_IT2_TIMEOUT_S:-10}"` (:658) with a settable `HANDOFF_IT2_TIMEOUT_BIN` seam (:659), plus `CC_IT2_TIMEOUT_S` default 5 s on the notify path (:307). So the fleet degrades instead of hanging and the restart is no longer forced. Steps (2)/(3) remain operator judgment, and the fleet has since moved to kitty (`51bdb524`, 08-09), so "45 panes, 110 sessions" is a 2-week-old census — re-probe before treating any of it as current.
c94cf98ab91f | UPDATE | Half FIXED. `bin/cc-notify` now exits **3** on an unset/empty role with `verdict=unresolvable reason=role-unset` (:690-695), and the header states it (:15). The lookup-miss-is-not-absence half this item actually wants — a role naming a pane ABSENT from a healthy registry must go non-zero, plus a liveness sweep on the role file — is not there. Keep the item's own two-directional positive-control requirement verbatim; that is the part a rebuild will skip.
449f29fad085 | UPDATE | Its cited precondition no longer exists. The item is scoped to "cc-roles/desk holds the CORRECT pane UUID and the invariant still can't resolve it" — today there is no `cc-roles/desk` file at all (measured: dir holds one 0-byte `orchestrator`), so the monitor's resolution path cannot be tested in the state described. It also names `desk-bootstrap 06` as the likely resolver; `06-desk-bootstrap-activate.sh` is on trunk AND `.done` in the live queue, so that hypothesis is already spent. Re-file as "the desk-recycle-invariant's pane→pid resolution, tested once a desk role exists again" and order it AFTER the role pointer.
0bcccfd6cd18 | UPDATE | The backlog arm has a producer now. `bin/cc-backlog` accepts `--run` on a `block`/`needs` record (:834, :1311-1375) and writes the field `run` (:649 fold, :1301 emit); `hooks/operator-readout.sh:381` reads `.run // .run_command`, so that consumer is satisfied. What remains producerless is exactly one arm: `:343` reads `.run_command` ONLY, off the cc-decide store, and `bin/cc-decide` has `--staged-artifact` (:128) and no run flag. Narrow the item to the cc-decide arm; the "no producer on trunk" headline is now false.
```

### MERGE (9)

```
0af4fc51f097 | MERGE | → 08ba1e3dccc2 (role cluster canonical). Same defect, and its stated fact has decayed one step further: it reports `cc-roles/desk = D40A5752…` (a stale pointer); today the file does not exist. Carry forward its unique contribution: the discriminating check (`cc-sessions` HEALTHY + target absent ⇒ genuine ABSENCE, not an unreadable registry) and the measured 839-message undrained box.
2dd61967cf64 | MERGE | → 08ba1e3dccc2. Its "cc-notify EXITS 0 on unresolvable" clause is REFUTED (exit 3, `bin/cc-notify:694`); everything else duplicates the canonical.
20ea2eed4e3e | MERGE | → 08ba1e3dccc2. Carry forward its unique and load-bearing finding: registry rows carry NO role field at all (paneUUID/name/cwd/account/pid/startedAt/session_id only), so role identity is unrecoverable from disk — that is why "refresh cc-roles on desk startup" cannot be the whole fix, and why its alternative (have handoff-fire record its `--notify-back` pane in the worker's registry entry) is the better shape.
fbb636e0201b | MERGE | → 08ba1e3dccc2. Same defect, thinner. Carry forward: every terminal completion-push records ALARM(UNRESOLVED) instead of delivering — that is the effect measurement f887a7a507db counts (265 records, 0 verified).
aedf7f6ac6df | MERGE | → 5deb4418a648. Identical claim ("consult the lease before minting a session"), same refutation applies (f61c1eaaba05: at fire time the lease answers dead). Carry forward its compounding observation: the item's own thrash record is what re-queues it, so an UNLANDABLE item is precisely the one that gets over-dispatched — that is the loop a3feeba64fe7 + 500765da985c close from the other end.
eb37a3c12cb4 | MERGE | → 5deb4418a648. Its headline is REFUTED by 6f24f9c49e3e: dispatch fired at 149789b69fc4 EXACTLY ONCE (dispatch-fires.log:3119) and its capacity gate correctly refused a fire 38 min earlier; the 16-session pile-up was Agent-tool recursion (see f2617b0480df). What survives and merges is the observation, not the attribution: N sessions in ONE worktree on a shared git index.
26897c0e94d0 | MERGE | → c163f42390a3. Its diagnosis "the wave writes ONE stamp for the whole wave" is refuted by the code — `mark_fired_peer` is called per fire with `$SPAWNED_PANE` (`scripts/handoff-fire.sh:5804`) — and by 3de96166b05b, which measured stamps PRESENT for three fires and ABSENT for two in the same window. It is a lost write on a specific path, not a per-wave design. Carry forward its one irreplaceable fact: a shared prompt file means all workers carry the SAME engagement marker, so **a marker match is not identity** — which is precisely the check `adopt_orphan_stamp` now relies on.
3de96166b05b | MERGE | → c163f42390a3. Same defect, better repro (panes 850/851, marker `HANDOFF-ENGAGE-68859-1786225862-25237` present in the prompt, `cc-fired/851.json` absent). Carry forward its two-defect split verbatim: (a) the duplicate fire, (b) the missing stamp that turns every duplicate into an un-retirable pane.
fd7ba0bbc359 | MERGE | → c163f42390a3, and this one carries the constraint the whole master item must respect. It already refutes three prior causes (UUID-vs-bare keying, claim-at-start, batch-unblock) and supplies the POSITIVE CONTROL: an operator-started ORIGIN session is ALSO unstamped and that is CORRECT — **a fix that stamps everything destroys the distinction self-close depends on**. It also names the existing owner (task #141) — attach there, do not open a fourth front.
```

### KEEP (43)

```
c163f42390a3 | KEEP | Canonical stamp item — best-controlled measurement in the slice (population restricted to registry rows named wt-* whose pid is ALIVE, so the raw 61/72 is correctly discarded as noise). 9 of 16 live dispatched peer panes unstamped, with named pane ids on both sides. Trunk has since gained the ADOPTION path (`scripts/handoff-fire.sh:4617` `adopt_orphan_stamp`, item 1467ea1dad4f) — but that only recovers a stamp whose PANE ID changed; it cannot recover a stamp that was never written, which is this item's case. Its same-item pane-PAIR pattern (752/753, 704/712 — one of each stamped) is the sharpest lead on trunk today.
8c60170a2037 | KEEP | Spawn-without-claim is a structurally different hole from the lease bugs and is UNCLOSED: guards 3/4/5 all live inside `cc-backlog claim`, so a spawn path that never calls claim is unguarded by construction. Its 3-panes/2-claims measurement is still the cleanest evidence. NOT YET DIAGNOSED (its own words) which spawner fired pane 344 — that diagnosis is the first move, and `28aa0b4c` "feat(pane-spawn-log): the eight panes nobody could name now each leave a row" (08-07 07:52) landed the instrument that can answer it.
08ba1e3dccc2 | KEEP | Canonical role item, and its premise has DECAYED IN THE WORSE DIRECTION, so update the text when you fold in the merges: `~/.claude/cc-roles/` holds exactly one file, `orchestrator`, and it is **0 bytes** — it no longer points at dead pane 390, it points at nothing. There is still no `desk`. Every dispatch brief on trunk ends with "then cc-notify the desk role (cat ~/.claude/cc-roles/desk)" (`bin/cc-dispatch:1272`), so every dispatched worker is instructed to page an address that cannot resolve.
a3feeba64fe7 | KEEP | Verified on TRUNK at the exact cited lines. `git show origin/main:bin/cc-dispatch` :681-682 — `if git show-ref --verify --quiet refs/heads/$br; then git worktree add "$wt" "$br"` — reuse takes the branch at its OLD TIP, and the `fetch` two lines above (:679) only feeds the else-arm, exactly as filed. No fast-forward, no ancestry assert.
fea435f6bdbe | KEEP | Verified on trunk; only the line number drifted (cited :1258, actual **:1292**): `if [ -n "$wcwd" ] && [ ! -d "$wcwd" ] && ! warm_worktree …` — provisioning is gated on directory EXISTENCE alone, so a re-dispatch reuses an existing tree with no fetch/reset/clean/ancestry check. Corroborating scale measured this session: **553 directories** under `~/Development/.worktrees/`.
500765da985c | KEEP | The generator behind the two above. Verified: the pin-at-filing-time consequence chain is exactly what :681-682 produces. Its fix direction (b) — have the worker DATE the item premise against trunk before writing code — is the one this slice's master item implements, and it is the cheap general case.
2228b5bf8477 | KEEP | Verified LIVE by direct read today: `git -C ~/Development/.worktrees/wt-592061637f80 status --short` still shows 8 staged (A) files including all four unlanded paid-asset paths — `assets/blender/clawd-bmo-{hero,portrait,three-quarter}.webp` and `tools/blender/clawd_bmo.py`. Nothing has drained it in 24 h+. Question (a) is an operator value call on paid assets; question (b) is the same defect as fea435f6bdbe.
42fd907d1459 | KEEP | Verified by reading the code on trunk. `cc-premise.cited_shas()` filters a token only when it is a PREFIX of a known 12-hex backlog id (`if any(i.startswith(tok) for i in known_ids)`), and `RE_SHA` is `\b[0-9a-f]{7,40}\b`. A session-id fragment like `7868b45e` is 8 hex and matches no backlog-id prefix, so it reaches `resolve_sha()` and renders "CITED SHA … no such object here (absent)". The item's cheaper alternative (relabel the line) is the right first cut; the adjacency test is the durable one.
0c5d47c863bf | KEEP | Verified absent. `cc-premise` detects DIRECTED refutation (`RE_VERB_ID` / `RE_ID_PRED`) and self-declared duplication (`RE_SELF_DUP`) — it has no notion of "a SIBLING item reached done AFTER this one's add ts". `git grep -i supersession origin/main -- bin` returns exactly one hit, a comment. This is a real gap in the gate that shipped, and its RED-proof is already written in the item.
62daeb7d4463 | KEEP | Verified on trunk: `bin/cc-backlog:681` still reads `elif $r.event == "unblock" then "open"` inside the last-transition-wins fold, with no terminal-state guard. Both of its separable defects stand, and defect (2) — documenting in `--help` that `done` is NOT gated by `blocked` — is a 5-line change that retires a whole class of ticket.
df2b6a40a5dc | KEEP | Verified: `git show origin/main:bin/cc-backlog | grep dispatch-projects.conf` returns NOTHING. The add path validates `--condition` hard (:755-768) and falls back to `project_default()` only when `--project` is ABSENT (:769) — an explicit `--project` is accepted unvalidated, exactly as filed. Its WARN-not-refuse instruction is correct and must survive the rebuild (the ledger is shared; a hard refusal would red other authors' gates).
7ff1b6f5ddbb | KEEP | Verified: `cmd_dups` on trunk still reports "same project+dodRef, live, not joined" (:1504, and the header at :31). `d4390e01` "the lease was on the row, so one condition with two wordings dispatched twice" (08-07) moved the LEASE to the condition but did not backfill pre-fix rows into condition groups, which is this item's second half.
4562ff2ad68e | KEEP | Verified on trunk at the exact cited line: `bin/cc-do:352` = `[ -t 0 ] || exit 0`, immediately after `render` and `[ "$NRUN" -gt 0 ] || exit 0`. The board prints, nothing runs, exit 0 — indistinguishable from a clean board.
9a14c2ef8224 | KEEP | Verified twice. `scripts/worktree-pool.sh` is absent from `origin/main` and `git log --all -- scripts/worktree-pool.sh` is empty — it has never existed. **16** tracked files still reference it, including `docs/WORKTREE_WORKFLOW.md`, `scripts/handoff-fire.sh`, `hooks/worktree-setup.sh`, `bin/cc-wave-plan`, and three tests. Delete-or-build is a real fork and the doc assertion is actively false.
f2617b0480df | KEEP | Verified absent: `git grep -n depth origin/main -- hooks/agent-teams-enforce.sh` returns nothing; there is no spawn-generation cap anywhere in the hook that gates Agent spawns. This is the actual multiplier behind the storm (6f24f9c49e3e: 1 → 6 → 36 → 216) and it is the single highest-leverage unfixed thing in the slice.
6f24f9c49e3e | KEEP | Correction record, not work — but do NOT close it out of the ledger: `cc-premise.find_correctors()` reads item TEXT from the append-only store, so this record is what stops a future worker rebuilding a dispatch-side fix for an Agent-recursion defect. Its own claim was checked against the code: cc-dispatch's capacity gate is real (`64a7d1fa` "the four spawn paths that bypassed the only hardware term", `38e2513b`).
bbad96d163ab | KEEP | Correction record. Load-bearing for the mechanism, not just the ledger: `bin/cc-premise`'s docstring names this exact id as its flagship case and derives the entire advise-don't-refuse design from it. Never delete.
7abb4b8fcbce | KEEP | Disproof record with a committed instrument (`tools/auth/auth-error-rate.py`). Its class A/B split is the reusable artifact. Its explicit "do NOT carry (a) or (b) forward" is exactly what the premise contract is for.
cdbfe751ccc5 | KEEP | Actionable record: it names 3 items to prune (499f6fb39fc1, 965acaf588fa, and the "12 uncommitted files / two incompatible decompositions" sub-premise of fd7ba0bbc359 and d6d8b259235d). All three targets are OUTSIDE this slice — hand to the lead. Its verify-first instruction (grep the id in backlog.jsonl and read the TRAIL, not the folded status) is the correct method and is the same read 62daeb7d4463 prescribes.
ba5511bbe388 | KEEP | Verified on trunk: `WANT_SELF_RETIRE` is set only at `scripts/handoff-fire.sh:5570` (`SELF_RETIRE=1 && RECYCLE=0`) and `mark_fired_peer` is called only inside `if [ "${WANT_SELF_RETIRE:-0}" = 1 ]` (:5803-5804), with the header stating "It must NEVER be written for an ordinary fire" (:2501, restated :4409). A launcher-spawned worker therefore cannot have a stamp, and its brief still orders `self-close --terminal`. The item's own fix direction (make the BRIEF agree with the launch mode, do not loosen the guard) is correct and matches fd7ba0bbc359's positive control.
82a4ee2b1a84 | KEEP | Premise intact and now sharper: there is still no `desk` role (measured, 0-byte orchestrator only), so the fallback it names is still dead. `55c18e2b` "address the back-channel by registry NAME — a bare pane id does not resolve" and `6507f517` "recycle relocates, and the back-channel is opt-out" (both 08-08) moved this surface; re-read the `--notify-back` resolution before rebuilding, but the resumed-session re-key is untouched.
0298535c1584 | KEEP | Untouched surface. Its fix direction (a) — cache the sessionId→pane map instead of live-querying per send — is the durable one and is complementary to the timeout work that landed in handoff-fire (`HANDOFF_IT2_TIMEOUT_S`, see 3c6bf04ba842): a bound turns a hang into a truthful 124, it does not make the send work. Direction (c) (callers treat 124 as UNDELIVERED) is the cheap half.
e91b6ef3d076 | KEEP | Verified by disk truth: `~/Library/LaunchAgents/com.claude.desk-invariant.plist` EXISTS but `launchctl list | grep desk` returns nothing — the daemon is staged and NOT loaded. So cc-notify's reroute decline does point at a remedy that never runs.
f887a7a507db | KEEP | Same disk truth, and this is the EFFECT measurement for the whole role cluster: 265 completion pushes, 0 verified, over 8 days, because the healer is unloaded. This is the number that argues the role cluster's impact.
ce91e9583df1 | KEEP | Verified the arm IS present and the item is still right that it did not take effect: `hooks/completion-assert.sh` exonerates only on `_ca_mine` rc **1** (`if [ "$_ca_d" -eq 1 ]; then _ca_exon=…dirty-not-mine`), and rc 2 ("cannot tell", the `return 2` at the end of `_ca_mine`) falls through to convict. No commit has touched this file since `0dd5c61f` (08-08), which was about the E0 per-turn oracle, not attribution. Its instruction to REPRODUCE before assuming rc==2 is the right first move — the discrepancy between the hook's result and the same oracle called by hand is the datum.
3208342f2f4c | KEEP | Both gates verified on trunk. GATE A: `hooks/waiting-recycle.sh` `disarm_for` is keyed on `$CFG|role:$DESK_ROLE|$CWD` with no TTL anywhere (:282, :365, :384-393). GATE B: `is_monitoring_desk()` (:216) reads `$COORD/cc-roles/$DESK_ROLE` with `DESK_ROLE` defaulting to `desk` (:205) — and that file does not exist, so arm-by-default is dead exactly as filed. Its "REMEDY IS NOT just run arm" clause is the part a rebuild will skip; keep it.
aabf363ff409 | KEEP | Verified absent: `git show origin/main:bin/cc-classify | grep -ci livelock` = **0**. There is no LIVELOCKED cause. Its four compounding defects are the most transferable content in the slice — especially (1) the extractor's ">60 chars" filter discarding the symptom and keeping the alibi, and (3) `idle_s=-1` as a NON-VERDICT that must ESCALATE rather than resolve to "active".
75e419843705 | KEEP | Verified: `scripts/lib/worker-claim-gate.sh` exists on trunk (landed `8cbf77d0`, "the refusal that reached only a journal now stops the write") and contains essentially no lead-vs-delegate vocabulary — the lease still models one worker per item. The orphaned-teammate half (TaskStop returned success on a live pid; both remedies permission-denied) is a second, separable defect and should not be folded away.
159c2211b0f2 | KEEP | Verified: `git show origin/main:hooks/lead-crash-watchdog.sh | grep -c watchdog.env` = **0** — it still does not source it; `LCW_ORPHAN_CLOSE` is read bare at :580. The item's own PREMISE CORRECTION (the arm is NOT inert; `~/.zshrc:675` does deliver it to interactive-zsh sessions) is the reason its value is now narrow — keep that correction attached, it is what stops a worker over-scoping this.
9260be0cc89c | KEEP | Untouched question. `d522809a` "account 1's launcher carries no digit, so pre-trust wrote where no session reads" (08-08) is the sibling fix it was found beside, not an answer to it. The item asks whether the trust dialog gates a headless `--permission-mode auto` launch AT ALL, and specifies the positive control. That control has not been run.
4ce34a4f703c | KEEP | Verified no checker exists: `ls scripts/*parity*` gives bats-shim, deploy-link (symlink parity), deploy-parity-assert, effort-parity-assert, iterm2-perf-parity, launchd-parity-lint — none enumerates `(event, script)` pairs across the five settings.json. The permission-rail consequence (what a session MAY DO depends on which account fired it) is the part that makes this urgent rather than tidy. NOTE ITS OWN ROUTING: handed to ROW 6 in `docs/ground-up-payloads/row6-guardrail-hooks.md`; it was filed separately deliberately because row 6 is last in dispatch order.
6bfd83f03c3a | KEEP | Product-side hazard with a working mitigation (route prose through a file; Write/Edit content and `git commit -F` are immune). Trigger still not isolated — the item says so. Do not let a worker "fix" this in the repo; its value is the mitigation rule.
ee1ac85c6ff6 | KEEP | Verified both halves. The guard's own header (`tests/tsv-field-collapse.bats:14`) says §3 "enumerates every `IFS=$'\t' read` in bin/ hooks/ scripts/" — an ANSI-C-quoting recognizer. Trunk contains the OTHER spelling at four sites in one file alone: `bin/cc-dispatch:772, 825, 869, 888` all use `while IFS="$(printf '\t')" read`. `bin/cc-bus:309` uses it for `sort -t`. So the census is structurally blind, exactly as filed. (Related, and the reason to be careful: `c2ccbeb8` shows the recognizer's false-positive direction has already bitten twice.)
1922427e1b84 | KEEP | Verified verbatim on trunk. `commands/compact-memory.md:224-232` still states 🚨 "`headroom_target` is NOT 17.1 KB — that demand is PRODUCT-SIDE and no honest pass can reach it", unconditionally, with the cardinality dependence visible in its own next sentence ("At this project's entry count it demands ~67 B/entry"). No `per_hook_budget` computation exists. The dropped-token audit instrument it names lives only under the reso project's memory archive — it is not in this repo, so "the only check that can prove non-lossiness" is currently unavailable to this project.
34b35fc074d7 | KEEP | The bench LANDED while this item was open — `scripts/hook-dispatch-bench.sh` is on origin/main (`ad09a4a5`, 08-09 15:58) with `tests/hook-dispatch-bench.bats`, and `a88392e2` "pin the control's DIAGNOSIS (biased vs underpowered)" landed the exact distinction this item names. So the item is now purely the RUN, on a quiet box. Deliberately NOT run here: the contract forbids long jobs and the box has 4 kernel panics this week — running the bench under this load would produce the same non-verdict the item exists to fix (memory: bound-must-fit-the-band).
05c79abca813 | KEEP | Same surface, one step behind: it asks to re-adjudicate `hook-chain.sh`'s shelving verdict on the occupancy axis, and the instrument it needs now exists (`ad09a4a5`). Its "wiring it is a c10 migration" note is the scoping constraint. Order AFTER 34b35fc074d7 — an unadjudicated ratio cannot re-adjudicate a shelving.
87a515ed087e | KEEP | Distinct from 3c6bf04ba842: that one is the operator's restart decision, this is the rc-SPLIT (a WEDGED resolver must not report as a dead pane/successor), mirroring the landed 0c93f779ecfa pattern. The bounds that landed (`HF_TIMEOUT_S`) make a wedge produce rc 124 — which is precisely when the conflation this item names becomes reachable, so the bound INCREASES its urgency rather than closing it.
8c62c7a963f2 | KEEP | Could not verify pane liveness — `~/.claude/live-sessions/` is empty on this box, so the registry this needs is elsewhere and the machine is under load. Per the contract that is "I could not tell", never PRUNE. Two notes for the lead: pane ids are volatile under kitty (renumber on restart), so re-resolve `367E9DA5-…` before acting; and its stated blocker (backlog 5690b9d11bee, `pane_proof grep -qxF` vs rich table) reads as already-addressed — `scripts/handoff-fire.sh:1608-1628` documents that exact `grep -qxF` failure and the fix. Re-check 5690b9d11bee's status before treating this as blocked.
7182929f693b | KEEP | Same class, same caveat: operator-only pane retirement, pane identity unverifiable from here. Its work is DONE and landed (3387b246) and its `--allow-dirty` justification is recorded — but that justification names ANOTHER session's 8 staged files, so re-read the tree before running it.
a7de672c34e3 | KEEP | Worktree `wt-149789b69fc4` still EXISTS on disk (verified). Session count unverifiable from here. This is the cleanup half of the storm; note the item's own constraint — the auto-mode classifier blocks `cc-reaper` as kill-adjacent, so the filer could not run its own prescription. That makes it operator-owned by mechanism, not by choice.
e06ba316a1aa | KEEP | Thin pointer item whose own title carries the right instruction — "re-measure the premise first". It gates steps 3/4 of the worktree-isolation rollout, which is the same surface as fea435f6bdbe/a3feeba64fe7; sequence it with them.
84e48ded804a | KEEP | Pointer to `cc-backlog b13787e71c9f` (Consolidation projects, audit 02) — that target is outside this slice. Hand to the lead for cross-cluster routing; do not fold.
c0de62c2b71c | KEEP | Verified the referenced artifact exists and is readable: `~/.claude/autonomy/feedback/banner-storyboard-feedback-2026-07-30.md`, 1410 B. Genuinely off this cluster's surface (banner/visual work) — route, do not fold.
```

---

## Master item(s)

Three, and the split is by ROOT CAUSE, not by convenience. Each has a different failure moment
(admission / retirement / supervision), a different file set, and closing any one leaves the other
two exactly as broken. The justification for each extra one is stated under "Why one effort".

---

### M-C-1 — Nothing fires until it is provably current, provably unclaimed, and lands in a provably fresh tree

**Encompasses:** `5deb4418a648` `aedf7f6ac6df` `eb37a3c12cb4` `f61c1eaaba05` `8c60170a2037`
`d6d8b259235d` `62daeb7d4463` `500765da985c` `a3feeba64fe7` `fea435f6bdbe` `0c5d47c863bf`
`42fd907d1459` `df2b6a40a5dc` `7ff1b6f5ddbb` `f2617b0480df` `75e419843705` `2228b5bf8477`
`e06ba316a1aa` — with `bbad96d163ab` `7abb4b8fcbce` `6f24f9c49e3e` `cdbfe751ccc5` as the
**corrector corpus it reads** (records, never worked, never deleted from the ledger).

**Why this is one effort.** One surface and one sentence: **`cc-backlog claim` is the only actuator
every fire passes through, and it currently answers three questions it should answer four of.** It
asks *is this item held* (guard 4, lease), *is it finished* (guard 3, done-latch), *can the work be
done where the worker is* (guard 5b, worktree oracle) and *is its premise standing* (guard 5,
cc-premise, landed `e4f73cb7`). It does **not** ask *is the tree this worker is about to be handed
current*, and cc-premise does not ask *has a sibling already landed this*, *what should be worked
first*, or *what one command would prove this dead*. Every item above is a face of that one missing
question, and they compound into a single closed loop that is measurable on disk today: a worktree
pinned at filing time (`bin/cc-dispatch:681-682`) hands a worker a tree older than the fix → the
worker reads the defect as present and re-derives it → rebase exit 5 → reopen → the thrash record
re-queues the item → it is re-dispatched into the *same* stale tree. `aedf7f6ac6df` states the
closure exactly: *an unlandable item is precisely the one that gets over-dispatched.*

The lease items are the same loop seen from the identity end. `f61c1eaaba05` is the one that must
govern the rebuild, because it kills the obvious fix: gating the FIRE on the lease cannot work, since
the lease key is a **dispatch-time shell pid** that is legitimately dead by the time the worker runs
(6 of 8 storm identities measured dead). The key has to outlive the work.

**Impact, argued from evidence.**
- It is upstream of the whole dispatch rail: **every** fire passes `cc-dispatch` step 5a → `cc-backlog claim`. A gate here binds all of them; a gate anywhere else binds one path.
- Measured cost per occurrence is a full worker slot plus its subagents — `5deb4418a648` names three workers on one item, two of which stood down after *full orientation* and one of which had already spawned five analysis subagents.
- The corpus is self-declaredly rotten at **16.5%** (CONCURRENCY_PROGRAM §S3: 55 of 333 items say CORRECTION/superseded/RETRACTED/"is FALSE" in their own text), and that is only the *self-declared* rate. cc-premise refuses 12 and advises 78 of 359 — so 78 items today are dispatched with a known-suspect premise and nothing but brief prose between them and re-deriving landed work.
- It touches enforcing stores directly: `bin/cc-dispatch`, `bin/cc-backlog`, `bin/cc-premise` are on `PATH`, symlinked live from this checkout. A change here is live at the trunk fast-forward, not at a future actor's discretion.
- Closing it retires 18 items in this slice and, by the mechanism rather than by the count, prevents the *class* — `df2b6a40a5dc` and `7ff1b6f5ddbb` are both "the store mints items no dispatcher can drain", which is the same gate one layer earlier.
- **553** worktree directories exist under `~/Development/.worktrees/` right now. That number is the accumulated exhaust of this loop.

**DoD.** On `origin/main`, gate-green and landed: (1) `bin/cc-premise` gains three derived reads —
a per-item **falsifier** (one shell command, stored or derived, whose exit 0 means "this item is
done or moot"), **cluster-as-dispatch-unit** (the condition/citation family is the thing claimed, not
the row), and a **derived rank** from the citation graph (an item that N others cite, or that blocks
the land rail, outranks an older unrelated one) — all fail-open, all advisory to the brief, none
able to starve the queue. (2) `order_dispatchable` (`bin/cc-dispatch:599-602`) consumes that rank
instead of `sort_by(_thrash, ts)`. (3) `warm_worktree` asserts freshness at HANDOUT: fast-forward to
base when the reused branch holds 0 unique commits, rebase-or-surface when it holds real ones, never
discard. (4) The lease key outlives the work (worktree-keyed or a dispatch-issued lease id), and the
spawn path cannot mint a session without one. (5) A sibling-done supersession warning fires at claim
with the RED-proof `0c5d47c863bf` already specifies. (6) An `unblock` on a terminal item refuses or
no-ops. (7) An explicit `--project` is validated against `scripts/dispatch-projects.conf` at add time
and **warns** (never refuses — the ledger is shared).

**Falsifier** — exit 0 means this whole effort is no longer needed:

```sh
cd ~/Development/claude-infrastructure && git fetch -q origin && \
git show origin/main:bin/cc-premise | grep -qi 'falsifier' && \
git show origin/main:bin/cc-premise | grep -qi 'rank' && \
git show origin/main:bin/cc-dispatch | grep -q 'worktree add "$wt" "$br"' && \
! git show origin/main:bin/cc-dispatch | grep -q 'worktree add "$wt" "$br"'
```

(The last two clauses are deliberately contradictory-looking: the third asserts the reuse arm is
still findable, the fourth asserts it is NOT the bare form measured today. Together they exit 0 only
when the bare `worktree add "$wt" "$br"` reuse at `:682` has been replaced. If a rebuild changes the
shape, re-anchor on `grep -q 'freshness at handout'`.)

**First move.** Answer `8c60170a2037`'s open question — **which spawner mints a session without
calling claim** — because every remedy below branches on the answer and the item explicitly forbids
assuming `cc-dispatch` (its step 5a *does* branch on claim rc). The instrument now exists: `28aa0b4c`
"feat(pane-spawn-log): the eight panes nobody could name now each leave a row" landed 2026-08-07. Read
the spawn log against the claim events for one storm item, and measure the spawn rc **against pane
liveness** (`d6d8b259235d`'s unproven hypothesis: a spawn that produced a real worker while the
dispatcher judged it failed and reopened). Do that before writing a line of gate code.

**Ordering within the effort.**
1. `8c60170a2037` — identify the unguarded spawner (measurement only, no code).
2. `f61c1eaaba05` — re-key the lease to something that outlives the work. Everything downstream depends on the key.
3. `5deb4418a648` + `aedf7f6ac6df` + `eb37a3c12cb4` — the spawn gate, built on (2), not on the shell-pid lease.
4. `a3feeba64fe7` + `fea435f6bdbe` + `500765da985c` — freshness at handout; these three are one diff.
5. `2228b5bf8477`(b) + `e06ba316a1aa` — the GC KEEP rule split (dirty-because-abandoned vs dirty-because-unlanded) falls out of (4). `2228b5bf8477`(a) is an operator value call on paid assets — file it, do not decide it.
6. `62daeb7d4463` + `d6d8b259235d` — the unblock transitions: refuse on terminal, gate on re-reading the block reason.
7. `42fd907d1459` — the 8-hex false signal. Cheap, and it removes noise from every brief the later work reads.
8. `0c5d47c863bf` — sibling-done supersession at claim.
9. The three derived reads in `cc-premise` (falsifier / cluster / rank) + `order_dispatchable` rewiring. **Last, deliberately** — a ranking built before (2)-(4) would rank items whose premises the earlier steps are still changing.
10. `df2b6a40a5dc` + `7ff1b6f5ddbb` — add-time hygiene, independent, can run in parallel with any of the above.
11. `f2617b0480df` + `75e419843705` — the Agent-recursion depth cap and the lead-vs-delegate relation. **Separable and safe to hand to a second worker** — different file (`hooks/agent-teams-enforce.sh`, `scripts/lib/worker-claim-gate.sh`), no shared hunk with 1-10.

---

### M-C-2 — A dispatched worker can prove who fired it, tell that originator, and retire its own pane

**Encompasses:** `c163f42390a3` `26897c0e94d0` `3de96166b05b` `fd7ba0bbc359` `ba5511bbe388`
`82a4ee2b1a84` `08ba1e3dccc2` `0af4fc51f097` `2dd61967cf64` `20ea2eed4e3e` `fbb636e0201b`
`c94cf98ab91f` `8c62c7a963f2` `7182929f693b` `a7de672c34e3`

**Why this is a SEPARATE effort from M-C-1.** M-C-1 is about admission — what may start. This is
about the **return path** — what happens when a worker finishes. They fail at opposite ends of a
session's life, share no file (`scripts/handoff-fire.sh` + `bin/cc-notify` + `~/.claude/cc-roles/`
vs `bin/cc-dispatch` + `bin/cc-backlog` + `bin/cc-premise`), and closing M-C-1 perfectly leaves every
finished worker exactly as stranded as it is today. The shared root **within** this item is one
sentence: **a fired worker's identity and its reply address are both written at fire time into stores
that the worker cannot repair, and both writes are currently lossy.** The stamp encodes "you were
fired, you may retire"; the role file encodes "here is who to tell". Nine live panes and a 0-byte
role file are the same missing write seen from two sides.

**Impact.**
- Measured effect, not inference: **265 completion pushes, 0 verified, over 8 days** (`f887a7a507db`) and **9 of 16** live dispatched peer panes unable to self-close (`c163f42390a3`). A pane that cannot retire holds its RAM, its worktree, and its slot forever — that is the direct feed into the 553-worktree pile M-C-1 is trying to stop generating.
- It is the mechanism behind three of this slice's own operator-only items (`8c62c7a963f2`, `7182929f693b`, `a7de672c34e3` — hand-close this pane, hand-cull those sessions). Closing it retires the *category*, which is why those three are inside it rather than filed as standalone chores.
- Every dispatch brief on trunk ends by instructing the worker to page `cat ~/.claude/cc-roles/desk` (`bin/cc-dispatch:1272`) — a file that does not exist. That is a guaranteed-failing terminal step on **every** dispatched item.

**The constraint that governs the whole rebuild** (from `fd7ba0bbc359`, and it is why this must not
be "just stamp everything"): an operator-started ORIGIN session is *correctly* unstamped, verified by
positive control on pane 694. `unstamped` is the correct encoding of "not a fired peer". A fix that
stamps every pane destroys the distinction self-close depends on and converts a safety refusal into a
silent pane-killer.

**DoD.** Landed on trunk: every fire writes a stamp keyed per PANE and the write is proven to survive
a double-fire into an already-provisioned worktree; a launcher-spawned (non-fired) worker's brief
emits **no** self-retire block (`ba5511bbe388`'s direction — fix the template, not the guard); a
`desk` role exists and is re-pointed on desk start; `cc-notify --role` goes non-zero when the role
names a pane absent from a **healthy** registry, with positive controls in BOTH directions (a live
role still delivers; a dead role goes non-zero); and the worker's reply address rides its registry
entry rather than a role file it cannot repair (`20ea2eed4e3e`'s direction — registry rows carry no
role field today).

**Falsifier:**

```sh
[ -s "$HOME/.claude/cc-roles/desk" ] && cc-notify --role desk "falsifier probe: reporting path live" 2>&1 | grep -q 'verdict=delivered'
```

Exit 0 means a desk role exists AND a page to it is accepted by a live target — the load-bearing half.
It does **not** cover the stamp half; pair it with a census of live `wt-*` registry rows lacking a
`cc-fired/<pane>.json` (the population control `c163f42390a3` already specifies: pid ALIVE only, dead
rows excluded, because `cc-reaper` legitimately clears stamps after confirmed teardown).

**First move.** Reproduce the LOST STAMP, not the missing role. `3de96166b05b` hands you a controlled
repro: two fires (panes 850, 851) into the *same already-provisioned* worktree `wt-5a5195f52793`, both
carrying handoff-fire's own engagement marker in their prompts, neither with a `cc-fired/<pane>.json`,
while three peers fired minutes either side of them *were* stamped. `mark_fired_peer` is called per
fire at `scripts/handoff-fire.sh:5804` and is best-effort by contract (returns 0 even when the write
fails) — so the first question is whether the call is reached at all on that path, or reached and
silently failing. Instrument the best-effort return before changing behaviour.

**Ordering.** 1. `3de96166b05b`+`26897c0e94d0` (repro the lost write) → 2. `c163f42390a3`+`fd7ba0bbc359`
(fix the write, preserving the origin distinction) → 3. `ba5511bbe388` (brief template agrees with
launch mode) → 4. `08ba1e3dccc2`+`0af4fc51f097`+`2dd61967cf64`+`20ea2eed4e3e`+`fbb636e0201b` (one desk
role, re-pointed on start, address carried in the registry row) → 5. `c94cf98ab91f` (fail-loud on a
dead role target, both positive controls) → 6. `82a4ee2b1a84` (resumed sessions re-key like
SessionStart does) → 7. `8c62c7a963f2`+`7182929f693b`+`a7de672c34e3` (the three hand-closures — do
them LAST, as the acceptance test that the rebuilt path retires panes on its own).

---

### M-C-3 — The autonomy loop's safety nets are armed by conditions that no longer exist, so every one abstains silently

**Encompasses:** `aabf363ff409` `ce91e9583df1` `3208342f2f4c` `e91b6ef3d076` `f887a7a507db`
`159c2211b0f2` `0298535c1584` `9260be0cc89c` `449f29fad085` `4ce34a4f703c`

**Why this is a THIRD effort.** M-C-1 and M-C-2 are about the work path. This is about the
**watchers** — and it is disjoint because every item in it fails in the same distinctive way, which
is neither admission nor retirement: **a supervisory mechanism reaches a non-verdict and reports it as
a healthy verdict.** `cc-classify` returns `active` via a FAIL-SAFE (`idle_s=-1`, "cannot prove idle")
and the session survives every sweep. `completion-assert` reaches rc 2 ("cannot tell") on attribution
and *convicts*. `waiting-recycle` abstains "disarmed" because a role file was deleted by an unrelated
cleanup. `desk-invariant` is staged and unloaded, so the healer for the dead role never runs.
`pre_trust` is a safety mechanism whose failure is silent *and* whose necessity is unmeasured. That is
one law — **alarm polarity: a mechanism that cannot answer must escalate, never resolve to OK** — and
fixing it in one place teaches nothing to the others, which is exactly why they should be one effort
rather than ten tickets.

Folding these into M-C-1 or M-C-2 would be wrong in a specific way: these are the mechanisms that
would have CAUGHT M-C-1's and M-C-2's defects. `f887a7a507db`'s 265-unverified count is the number
that made the role cluster visible at all. A rebuild that fixes the work path and leaves the watchers
abstaining ships the next generation of the same silence.

**Impact.** The operator is currently the fallback sensor for this whole layer, and `aabf363ff409`
records the cost precisely: three panes burned ~4 h in a goal-hook loop, a full desk sweep an hour
earlier scored all three KEEP, and the **operator** caught it from the rendered panes. That is the
system asking a human to be its liveness oracle. `ce91e9583df1` is worse than a miss — it actively
pushes sessions to violate CLAUDE.md's G4 by committing a sibling's work in a shared checkout.

**DoD.** `cc-classify` gains a LIVELOCKED cause that grades behaviour over TIME (repetition across
turns), not last-message content, and its non-verdicts escalate as their own decision item rather than
resolving to `active`. `completion-assert`'s rc-2 path is reproduced and fixed so "cannot tell" never
convicts. The `waiting-recycle` disarm marker gains a TTL and a live arm-state readout. The
`desk-invariant` daemon is loaded (operator step — **file it**, it is a `launchctl` action).
`lead-crash-watchdog` sources `watchdog.env` itself, fail-soft. `cc-notify`'s pane resolution is
cached so a send survives load. `pre_trust`'s necessity is established by the positive control
`9260be0cc89c` already specifies, before anyone prunes it or relies on it. `4ce34a4f703c` gets a
cross-config-dir `(event, script)` parity checker.

**Falsifier:**

```sh
launchctl list | grep -q com.claude.desk-invariant && \
git -C ~/Development/claude-infrastructure show origin/main:bin/cc-classify | grep -qi 'livelock'
```

Exit 0 means the healer is loaded AND the classifier has a livelocked cause — the two poles of this
effort. (Neither is true today: `launchctl list | grep desk` returns nothing though the plist is
staged in `~/Library/LaunchAgents/`, and `grep -ci livelock` on trunk's `cc-classify` = 0.)

**First move.** Reproduce `ce91e9583df1` — run `hooks/lib/session-writes.sh`'s oracle by hand against
the named transcript (session `44dc8891-3590-4b21-b5b5-d8a617a39505`, config dir `~/.claude-quaternary`)
and against the payload the Stop hook actually supplied, and find where the two diverge. The item is
explicit that the cause is NOT isolated and forbids assuming rc==2 — the divergence between the hook's
`_ca_mine` result and the same oracle called directly is the datum, and the candidates it names
($TP vs the transcript actually read; $CWD resolution in a linked worktree) are testable in minutes.
Do this first because it is the only item in M-C-3 that is actively causing damage rather than
failing to prevent it.

**Ordering.** 1. `ce91e9583df1` (stop the active harm) → 2. `aabf363ff409` (the livelocked cause; its
four defects are the design spec) → 3. `3208342f2f4c` (TTL + arm-state readout; depends on M-C-2's
desk role existing for gate B) → 4. `e91b6ef3d076`+`f887a7a507db` (load the daemon — **operator step,
file it with `cc-backlog needs --run`**) → 5. `159c2211b0f2` (env provenance, narrow) → 6.
`0298535c1584` (cache the pane map) → 7. `9260be0cc89c` (the pre_trust control) → 8. `449f29fad085`
(re-test once a desk role exists) → 9. `4ce34a4f703c` — **but see the routing note below; this one
probably is not yours.**

---

## Notes for the lead

**1. The single biggest correction to this slice's framing.** `bin/cc-premise` is not a design — it
shipped 2026-08-07 (`e4f73cb7`), is wired into BOTH consumption points, is tested (21 tests, every
refusal paired with a near-miss control), and CONCURRENCY_PROGRAM §S3 is marked LANDED with results
(12 refuse / 78 advise / 0 auto-closed). The brief should be written as *extend the gate that exists*,
not *build the gate*. Three of its design decisions are load-bearing and a rebuild will violate all
three unless the brief says so: (a) **it advises and almost never refuses** — refusing an item with
one refuted sub-claim strands the real work beside it, which is why the flagship case `23eccae755a9`
is *allowed* to be claimed with the disproof riding the brief; (b) **the worker's enforcing store is
its BRIEF, not the exit code**; (c) **fail-open by construction** — only exit 3 blocks, every sensor
failure exits 0, because an unread premise is "I could not tell", never "it is finished".

**2. FIFO-oldest-first is confirmed, and the fix has a precise location.**
`bin/cc-dispatch:599-602`, `order_dispatchable()` = `sort_by(._thrash, (.ts // .lastTs // ""))`.
Thrash ASC then timestamp ASC; `jq`'s `sort_by` is stable. No priority or severity field is read
because none is written. That one jq expression is where a derived rank lands.

**3. Cross-cluster routing — four items are not mine and I did not fold them:**
- `4ce34a4f703c` (hook-wiring parity across the 5 config dirs) states in its own body that it was **handed to ROW 6** in `docs/ground-up-payloads/row6-guardrail-hooks.md` and filed separately only because row 6 is last in the dispatch order. If another cluster owns hook wiring, it belongs there; I placed it in M-C-3 as a holding position, not a claim.
- `84e48ded804a` points at `cc-backlog b13787e71c9f` (Consolidation projects, audit 02) — outside this slice entirely.
- `c0de62c2b71c` (banner storyboard, 5-point operator feedback) is visual/creative work; the referenced file exists and is intact.
- `1922427e1b84` is a `/compact-memory` spec defect (`commands/compact-memory.md`), a memory-hygiene surface, not dispatch. If a memory cluster exists it is theirs; I verified the claim is still verbatim on trunk either way.

**4. `cdbfe751ccc5` gives you three PRUNEs in other slices, free.** It establishes with a ledger read
that `499f6fb39fc1` and `965acaf588fa` rest on a false premise ("blocked prevents owner 695 from
closing it" — `done` is not gated by `blocked`, verified twice), and that the "pane 695 holds 12
uncommitted files / two incompatible decompositions" fact cited by `fd7ba0bbc359` and `d6d8b259235d`
is false (695's tree is clean, work landed and content-verified). Its verification method is the one
to apply: **grep the id in `~/.claude/autonomy/backlog.jsonl` and read the TRAIL, not the folded
status** — because `unblock` un-completes a done item (`62daeb7d4463`, verified live on trunk at
`bin/cc-backlog:681`). Any cluster reading folded status is reading a lie for at least that one item.

**5. Landmine for whoever runs the next triage.** The shared checkout was **19 commits behind
`origin/main`** the entire time. Six commits in that gap (`ad09a4a5`, `a88392e2`, `8d3f4acb`,
`e0adb128`, `ca7db1a1`, `437ccc0b`-adjacent docs) bear directly on items in this slice —
`scripts/hook-dispatch-bench.sh` reads as *absent* from the working tree and is *present* on trunk.
If any other agent triaged from a working-tree read rather than `git show origin/main:`, their KEEPs
are unreliable in exactly the direction that matters. This is the same defect as `500765da985c`
(dispatch worktrees pinned at filing time) wearing a different hat, and it is worth stating in the
merged output as a method rule: **triage reads `origin/main`, never the checkout.**

**6. Three items are operator-owned by MECHANISM, not by choice** — `a7de672c34e3` says the auto-mode
classifier blocks `cc-reaper` as kill-adjacent, and `3c6bf04ba842` / `8c62c7a963f2` / `7182929f693b`
all need a pane action an agent cannot take. File each with `cc-backlog needs --run "<cmd>"` so they
render in the `OPERATOR ▸` block instead of sitting in the dispatch queue burning selection passes.
Same for loading `com.claude.desk-invariant` (staged in `~/Library/LaunchAgents/`, absent from
`launchctl list`) — that is a `launchctl` action and it currently blocks the self-healing of the
entire role cluster.

**7. Two things I deliberately did NOT do**, per the contract: I ran no test suite (`34b35fc074d7`
and `05c79abca813` both want a bench run; the box has 4 kernel panics this week and a bench under this
load reproduces the exact underpowered non-verdict those items exist to fix), and I did not verify
pane liveness for `8c62c7a963f2` / `7182929f693b` / `a7de672c34e3` — `~/.claude/live-sessions/` is
empty on this box, so the registry is elsewhere and I marked all three KEEP-with-note rather than
guessing. Under kitty, pane ids renumber on restart; every one of those three must re-resolve its
target before acting.
