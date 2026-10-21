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
| W5 | C | lrsl-w5 | `fef98e423` `1f1e42206` `a294d2bcb` | live-wall reads only (shadow would-defer lines; detect→PLANNED from telemetry) | L flip `LRP_RF_MODE` shadow→on in `lr-reset-poller.sh` `lrp_rf_init`, after packet `4ffc4e1e5f1c`, before W16 starts or riding W16 |
| W6 | A | lrsl-w6 | `8f4ab29f9` `748186142` | cure run: role_ms ≤3 ms, census cpu ≤20 ms, per load bin | — |
| W7 | C | lrsl-w7 | `29fa7e597` | none | operator RK step `626ed25b243c` due |
| W8 | A | lrsl-w8 | `72fc09748` | pair `--red tree:a294d2bcb@31`: cure H1-H9, c_rpc_fail_twice ENGAGED cure / ESCALATED red | target:W8 flip in `load-expect.json` after that run |
| W9 | A | lrsl-w9 | `784682330`, `9700c6213` (swap-slot race) | T2 `--red tree:72fc09748@31`: P_obs ≤180 s → XPASS | `load-expect.json` T2 row → hard after the XPASS |
| W10 | A | lrsl-w10 | `52fc6f2b8` (+ DaemonWiring hermetic) | pair `--red tree:054ca06bb@31`: place events carry `holds=n/n holds_s=` | post-R3 production band report: `/tmp/w10h/holds_report.py` |
| W4 | B | lrsl-w4 | `30cadb316` `354bd4c04` `da293caf2` (bats 1..58 0 not ok, 34/34 mutants; custody returned 01:49) | own pair guarantee9 `--arms cure,red` (cure-only and pair ran NO-VERDICT: load 9.6-11.2/core, containment) | — |
| W4b | B | lrsl-w4b | IN FLIGHT pane 359 (fired 2026-10-21 01:21) | — | grants: `load_lib.py`, `stub-claude.py` (standing: W4's rig files except `load-expect.json`/`g1-allow.tsv`), `scripts/lib/pane-placement.sh` (skip rig OS windows, W4 finding) |
| W12 | C | lrsl-w12 | IN FLIGHT pane 267 (fired 22:40) | — | carries `lr-guarantee-g1-lint.bats:415` deletion |
| W11 | A | lrsl-w11 | IN FLIGHT pane 304 (fired 23:46) | — | removes `g1-allow.tsv:25` (hf_lr_admit debt:W12) if W12 landed |
| C2 re-open | — | — | backlog `649ebd06939f`, blocked not-yet-true | — | — |

Next per slot (Phase 0 order and edges): A W13 → W14 → W17 · B W4b → W15 → W16 · C W12b (after W12).

## Operator

- R1+R2 reload ran 2026-10-21 02:30Z (`lr-band-reload` verdict=ok, daemon at 31T; restarts.jsonl carries
  `inflight`/`inherited`/`prev_phase`; telemetry rows present).
- R3 (W9+W10) is DUE now: standing step `b8bbc2317870`, `bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm lr-band --now`.
  Read-back: heartbeat has `pass_at`, `pages_queued`; the next place event carries `holds=n/n holds_s=`.
- RK (W7) is DUE: step `626ed25b243c`, dry run `lr-band-reload.sh --keepwarm` then `--confirm keepwarm-band`.
- B8 kitty restart (step `1c94119a286d`): W7's live status WARNs restore-fd-gate (208 lsof rows > CC_RESTORE_FD_MAX 180),
  so a second cc-restore round would stop.

## Learnings for the lead

- Waves ask for one-file grants outside their ownership row when a lever reddens another wave's test. Grant when no
  in-flight wave writes the file, with "rebase right before landing"; standing grants cut round trips.
- `handoff-fire.sh` refuses a brief whose `cc-notify` target is a pane number; use the lead's full session uuid.
- The capacity gate refuses once at 8 active sessions and admits the next fire; the helper retries once.
- Land smoke is shed above load 80; every wave re-ran its own suites after the land.
- Tier-L queue (2026-10-21 01:19 and 01:24, successor lead): `preflight --matrix guarantee9 --arms cure,red`
  read NO-VERDICT twice on kitty limits, not load (29.8/core): kitty fds 151+3×36=259 > 230 and coalition
  697+4×34=833 > 650. Both fall only with fewer panes or the B8 kitty restart (`1c94119a286d`); retry per slice.
- Unexplained, out of scope: `cc-lr status --rail` showed `dispatch 4 ×2` (two processes at base priority 4) while
  `com.claude.dispatcher` is loaded Interactive.
