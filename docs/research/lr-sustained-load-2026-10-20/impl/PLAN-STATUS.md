# LR sustained-load plan: lead status (succession at W10, 2026-10-20 23:50 CDT)

Plan: `docs/plans/LR_SUSTAINED_LOAD_IMPL.md`. Disposition of every lever: `REPORT.md` §8.1.
Lead pane 187. Every wave was fired with `--notify-back 187`, so pings and custody land in this pane
whichever session holds it. Fire kit (template + helper): `impl/lead-kit/` (copied from /tmp).

## Waves

| Wave | Slot | Branch | Landed sha | Owed Tier-L (run by the lead once W4 lands) | Pending |
|---|---|---|---|---|---|
| W0 | L | lrsl-remaining-lead | `dc13d1a09` plan, `f5f50e512` filings | — | — |
| W0b | — | lrsl-w0b | `3471aebea` `d8fb9210b` `79090c717` `9f005ae66`, grown `b24389ff7` (lr-predicate `-I`) | — | — |
| W1 | B | lrsl-w1 | `e6713c4da`..`2d99d8e93` (S5b hard `a12101b6c`) | none | — |
| W2 | A | lrsl-w2 | `1eb5548ac` `45b8bbfa9`, `288b5f897` (wave_g test fix) | guarantee9 `--arms cure,red --red tree:c79df708d@31`; expect T4 PASS cure / FAIL red | — |
| W3 | C | lrsl-w3 | `c79df708d` | none | — |
| W5 | C | lrsl-w5 | `fef98e423` `1f1e42206` `a294d2bcb` | live-wall reads only (shadow would-defer lines; detect→PLANNED from telemetry) | flip shadow→on DONE 2026-10-23 (packet `4ffc4e1e5f1c` default fired; row `fa97d2db22d1`) |
| W6 | A | lrsl-w6 | `8f4ab29f9` `748186142` | cure run: role_ms ≤3 ms, census cpu ≤20 ms, per load bin | — |
| W7 | C | lrsl-w7 | `29fa7e597` | none | operator RK step `626ed25b243c` due |
| W8 | A | lrsl-w8 | `72fc09748` | pair `--red tree:a294d2bcb@31`: cure H1-H9, c_rpc_fail_twice ENGAGED cure / ESCALATED red | target:W8 flip in `load-expect.json` after that run |
| W9 | A | lrsl-w9 | `784682330`, `9700c6213` (swap-slot race) | T2 `--red tree:72fc09748@31`: P_obs ≤180 s → XPASS | `load-expect.json` T2 row → hard after the XPASS |
| W10 | A | lrsl-w10 | `52fc6f2b8` (+ DaemonWiring hermetic) | pair `--red tree:054ca06bb@31`: place events carry `holds=n/n holds_s=` | post-R3 production band report: `/tmp/w10h/holds_report.py` |
| W4 | B | lrsl-w4 | `30cadb316` `354bd4c04` `da293caf2` (bats 1..58 0 not ok, 34/34 mutants; custody returned 01:49) | own pair guarantee9 `--arms cure,red` (cure-only and pair ran NO-VERDICT: load 9.6-11.2/core, containment) | — |
| W4b | B | lrsl-w4b | `1e52a4b3d` `d5850fc77` (pane-placement skips rig windows) `c8a26b0d6` `0fd7ced3c` (T5 fixture), 14/14 paths verified; rig-move-lane 1..24, pane-placement 1..16; custody returned 05:00 | move9 pair `--red tree:1f1e42206@31`: cure T5 XPASS, red T5 XFAIL (W4b's own try `20261021T090311Z8abf` was NO-VERDICT at preflight); then `load-expect.json` T5 → hard | grants: `load_lib.py`, `stub-claude.py` (standing: W4's rig files except `load-expect.json`/`g1-allow.tsv`), `scripts/lib/pane-placement.sh` (skip rig OS windows, W4 finding) |
| W12 | C | lrsl-w12 | `c85b7063b` (9/9 paths verified; 5 suites green under bash 3.2; custody returned 04:17) | — | identity flip to `on` after ≥30 `recycle-kid-shadow` rows in `~/.claude/logs/handoffs.jsonl` with 0 disagreements. 0 rows at 04:14: no session has recycled since the emitter went live (last recycle 05:17Z). Not met at W12b's land, so it is an L commit after W15 lands |
| W11 | A | lrsl-w11 | `b54efff86` `c8c922dc8` `ed6f47072` (925 unittest OK, bats 1..46; custody returned 03:26) | guarantee9 + guarantee30 pairs `--red tree:52fc6f2b8@31` (guarantee30 needs W4b), expect T1 PASS cure / FAIL red | T1 → hard in `load-expect.json` after those runs; `g1-allow.tsv:25` removal routed to W13 |
| W13 | A | lrsl-w13 | `ef94cd89c` (A7 C+D, D2a switch) + `0022f026d` (`g1-allow.tsv:25` debt row dropped); 946 unittest OK, fence bats 0 not ok, 22/22 mutants; custody returned 04:24 | guarantee30 pair, arm `idle_fanout_switch`, `--red tree:ed6f47072@31`: idle groups MOVED via fan-out with `recon/idle-fanout.on`, limited T1 unchanged | R4 reload filed as step `3853d91f9626`; kill switches added to `LIMIT_RECOVER_FLEET_V2.md` |
| W12b | C | lrsl-w12b | part 1 `ac25e898e` (3/3 paths verified; typed-relaunch-hold 1..9, probe-preconditions 1..13, 6/6 mutants); custody returned 04:31 | W4 typed-relaunch group with `printf terminal > ~/.reso/limit-recover/typed-relaunch-hold.mode` for the run only: 0 HOLD-LOAD | after that run, resolve `debt:typed-relaunch` in `g1-allow.tsv` (slot A); part 2 after packet `db44ab0ebc55` |
| W14 | A | lrsl-w14 | `4b4edf0de` (10/10 paths; 979 unittest OK, pane-bind-env 33 OK; live shadow census 36/36 agree; custody returned 05:28) | kitty-deaf.json: arm on (`printf on > recon/pane-bind-env.mode` in the rig root) binds 6/6 by env, arm shadow binds none; `--red tree:ef94cd89c@31` | R5 reload step `7f151e71f291`; its now-audit finding (case 15 mutant void since W11) fixed by the lead, `cfdb341d2` |
| W17 | A | — | PARKED | — | entry trigger unmet: packet `4ab193daae88` unruled (deadline 2026-11-03), R4 not live, no measured wall and no failing guarantee9 cure run. Row stays FILED |
| W15 | B | lrsl-w15 | `83e99fccc` + 3 fixups to `01fee6a42` (5/5 paths; repick 1..52, recovery-lane 1..42, 31/31 mutants; custody returned 06:11) | — (a ≥30/core latency bin is owed before mode `on`) | mode `off`; packet `0223cae3d185` sets it |
| W16 | B | lrsl-w16 | `abb17fa10` `d0ffedbfe` (per-arm rig env, granted `load_lib.py`) + 3 fixups to `721539ac6`, 12/12 paths verified; post-land 1..123 0 not ok; custody returned 07:51 | E1 pair `--matrix tests/rig/faults/shed-e1.json --red tree:0ae7363f8@31 --arm-env red:LR_RIG_MOVE_SLOTS=4` (PASS with power); T6 needs a rig matrix that runs `lr-shed.py --tick` in an arm (not built) | shadow only (packet `76a584cc935b`; shadow step `f259e20643bf`). D13 replay (`/tmp/d2w16/REPLAY.md`): the coded rule avoids 4-6/43 walls at L30 and 3-5/43 at L45, not the 15/43 the design claimed, because `select()` spends the 4-per-look budget on cold, days-dormant sessions. That is input for the packet's `on` ruling. Kill switches added to `LIMIT_RECOVER_FLEET_V2.md` |
| W14f | A | lrsl-w14f | `b8ce080ca` (3/3 paths; 991 unittest OK, shadow 1..28, phase 1..5, red proof 2 cases, 8/8 mutants; custody returned 08:12; activates with R5). Scope (grown): +census ignores a session row whose pid was reused (H5 root cause, `/tmp/lrsl-h5-splitbrain.md`, 93%) | re-run the W2 guarantee9 pair after it lands | files: `observe_rows.py`, `observe.py`, new `test_session_row_reuse.py` |
| C2 re-open | — | — | backlog `649ebd06939f`, blocked not-yet-true | — | — |

Next per slot (Phase 0 order and edges): A W14 → W17 · B W15 → W16 (W16 also needs the W5 Part A flip, packet `4ffc4e1e5f1c`) · C done after W12b part 1.

**Closing state (2026-10-21 08:20 CDT, successor lead):** every buildable wave is landed. W17 is parked behind its
entry trigger (packet `4ab193daae88`). Open lead work is in parked backlog rows: the owed Tier-L queue
`bbe7b5b1ba63`, the W12 identity flip `a76128229b2a` and the W5 Part A flip `718ef4662d91`. Operator: the reconciler
reload R4+R5 (one run covers both; steps `3853d91f9626` and `7f151e71f291`), the D2b shadow step `f259e20643bf`, and
the B8 kitty restart `1c94119a286d`.

## Operator

- R1+R2 reload ran 2026-10-21 02:30Z (`lr-band-reload` verdict=ok, daemon at 31T; restarts.jsonl carries
  `inflight`/`inherited`/`prev_phase`; telemetry rows present).
- R3 (W9+W10) RAN 2026-10-21 ~08:06Z (verdict=ok). Lead read-back 08:08Z: reconciler pid 70188 `pri=31 ok`, heartbeat
  carries `pass_at` and `pages_queued`; no `place` event since the reload yet, so the `holds=` read is still to do.
- RK (W7) RAN 2026-10-21 ~08:07Z (verdict=ok; keepwarm and accounts-local at band 31, spawn type interactive).
- Both steps were closed `done`, including `b8bbc2317870`, which named R1-R5. R4 (after W11+W13) and R5 (after W14)
  therefore need new steps: the lead files each when its waves land.
- B8 kitty restart (step `1c94119a286d`): W7's live status WARNs restore-fd-gate (208 lsof rows > CC_RESTORE_FD_MAX 180),
  so a second cc-restore round would stop.

## Learnings for the lead

- Waves ask for one-file grants outside their ownership row when a lever reddens another wave's test. Grant when no
  in-flight wave writes the file, with "rebase right before landing"; standing grants cut round trips.
- `handoff-fire.sh` refuses a brief whose `cc-notify` target is a pane number; use the lead's full session uuid.
- The capacity gate refuses once at 8 active sessions and admits the next fire; the helper retries once.
- Land smoke is shed above load 80; every wave re-ran its own suites after the land.
- Tier-L queue order (landing order): W2 g9 · W6 cure · W8 pair · W9 T2 · W10 pair · W4 pair · W11 g9+g30 · W4b move9 ·
  W12b typed-relaunch · W13 g30 idle-fanout · W14 kitty-deaf. At 05:28 kitty fell under both limits (227/230, 601/650)
  and the W2 pair started: run `20261021T102850Z9471`.
- W2 guarantee9 pair, two tries: `20261021T102850Z9471` (cure 1a7e5ac68) and `20261021T120053Zdc2a` (cure 0ae7363f8),
  both NO-VERDICT on the premise (20% and 2% of samples ≥15/core; load fell after each spike). Both showed A6 power
  (H3 XPASS cure, XFAIL red). Both cure arms FAILED hard check H5 with split-brain 1. Root cause, read-only, 93%: pid
  reuse. `observe_rows.read_session_rows` accepts a stale `sessions/<pid>.json` row without comparing `procStart`
  (since ab51142a24), and the rig stub leaves its row behind on SIGTERM. The red arm has the same defect and passed only
  because its records fell in an unread cohort. This is a latent production defect, not a regression from this plan.
  Fix wave W14f.
- `lead-kit/brief-template.txt` names the lead's session uuid for detail pings. A recycled lead must rewrite it to its
  own uuid at once; until 04:20 waves sent their long reports to the retired session's mailbox (read it with
  `~/.claude/mailbox/<old uuid>.md`).
- Tier-L queue (2026-10-21 01:19 and 01:24, successor lead): `preflight --matrix guarantee9 --arms cure,red`
  read NO-VERDICT twice on kitty limits, not load (29.8/core): kitty fds 151+3×36=259 > 230 and coalition
  697+4×34=833 > 650. Both fall only with fewer panes or the B8 kitty restart (`1c94119a286d`); retry per slice.
- Unexplained, out of scope: `cc-lr status --rail` showed `dispatch 4 ×2` (two processes at base priority 4) while
  `com.claude.dispatcher` is loaded Interactive.
