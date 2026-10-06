# q6 — the command surface today against the wanted two commands

Read and measured 2026-10-06 06:38-06:42Z in `/Users/chrisren/Development/.worktrees/lr-zero-memory`. Tags: MEASURED = I ran it; READ = source or record; INFERRED = derived. Line numbers are this worktree's.

Ran (all read-only): `cc-lr find --limited`, `cc-limited --json`, `cc-lr move --status <batch>`, `cc-lr accounts --limited`, a `/bin/bash -c` parse repro, `jq`/`ps` over the registry. Not run: `cc-lr plan`, `cc-lr move --dry-run`, `cc-lr switch --dry-run` (their census reads every candidate pane's composer over a kitty RPC, `scripts/lib/cc-tui.sh:143-146,158`, and `move --dry-run` calls `claude-accounts --rank general --fresh`, `bin/cc-lr:784-785`), and `claude-accounts --json` (not proven free of a usage sweep).

## Verdict

- The surface already has both halves, under names that hide them. `cc-lr recover --limited --account A` lists and acts in one call (limited sessions through the recover lane, A's idle sessions through the move lane). `cc-lr plan --from A --to B` is the read-only list.
- Four gaps separate that from "one list, one rotate": no fleet-wide form, busy sessions are printed and dropped, "needs rotation" means exactly 100% and nothing below, and verdicts come back through two unrelated channels.
- Memory is a possible NOTMOVED reason on this surface (`lr-move-worker.sh:128-135`, `lr-move-batch.sh:151-155`) and it did not fire in the one recorded batch: 0 of its 8 capacity logs hold a refusal, and no verdict carries `capacity:` (MEASURED `grep -l -i refus`). The two caps that show in records are fixed numbers: the single-session lane's 2 (38 of 480 `fleet/one-2026*` runs logged "the --one lane is at its cap (2 live recoveries)", MEASURED `grep -l`) and the move lane's slot width 4 (READ `lr-move-lib.sh:179`; `slot-wait` detail "width 4" in the batch's events).

## 1. Verb by verb

| verb | selects | lists or acts | target | busy now | output |
|---|---|---|---|---|---|
| `cc-lr find --limited` (execs `bin/cc-find`, `cc-lr:2206-2207`) | every registry row, any liveness, whose transcript's last assistant record is a limit error (`cc-find:335-350`, `lr-lib.sh:174`). Teammates dropped from the candidate set (`cc-find:207-212`). No account filter. Not idle, not busy | lists | none | not applicable | TSV `sid pane account cfg cwd liveness class`; rc 0 rows, 1 none. MEASURED: 17.7 s wall, 0 rows, rc 1 (load average 33-64) |
| `cc-limited --json` | sids with a stop-failure marker row of any cause, plus parked records (`cc-limited:204-273, 806-832`); 24 h window, weekly caps always shown (`:835-840`); `--account` filters on the account the session is on now (`:738-740, 1239-1240`). Teammates listed as state TEAMMATE (`:748`). Sees no healthy session | lists (writes only under `ack` and `--reaper --persist`, `:1007-1025, 1073-1076`) | none | not applicable | one JSON object `{now, sessions, unaddressable, degraded, absent, rows[38 keys]}`, 12 states (`:744-787`); rc 0, 6 degraded, 5 instrument. MEASURED: 2.2 s, 97 sids, 7 rows in window, all RE-ENGAGED |
| `cc-lr recover --limited [--account A] [--target T]` (`cc-lr:441-510`) | limited half: `cc-find --limited` rows filtered by config-dir basename (`:455-462`). Idle half: only with `--account` and only when A reads >= 100% weekly or 5-hour (`:426-440, 484-487`): A's idle sessions minus the ones just fired (`:502`) | acts. Limited: `cmd_recover` per sid in a subshell, which fires `lr-fleet.sh --one --detach` (`:464, 572`). Idle: `cmd_switch_driver` then `cmd_move` then a poller batch (`:502, 873`) | limited: `auto` is resolved per session inside lr-fleet (`lr-fleet.sh:760`). Idle: `--target`, else ONE account for the whole set from `claude-accounts --rank interactive`, tier >= 2, never the source (`cc-lr:701-724`) | idle half passes until-idle 0, so mid-turn, subagents, background-job and composer-unknown rows print `hold:<d>` "busy now; --until-idle S waits for it" and are not queued (`:502, 1095-1097`). The verb accepts no `--until-idle` (`:445-449`) | 3 lines per fired session (`:597-602`), a count line (`:475`), then the move table and `batch <id> queued`. Limited verdicts arrive as mail only. rc 0 when anything fired or a batch is on disk (`:509`) |
| `cc-lr switch --from A --all-idle --target T` | same as `move` | delegates to `cmd_move` unless `CC_LR_SWITCH_LEGACY=on` (`cc-lr:871-874`) | explicit only; `auto` refused rc 3 (`:837-840`) | skipped unless `--until-idle S` | `move`'s |
| `cc-lr plan --from A --to B [--until-idle S] [--cold-only] [--json]` (`cc-lr:1162-1193`) | every live registry row on A, stale rows, and A's background sessions, one row each (`lr-upgrade.sh:910-1009`), plus the lane holds: limited, api-error, in-flight claim, live /goal, warm cache (`cc-lr:1105-1125`) | lists; pinned read-only by `tests/lr-move-plan.bats:105` | must be named; needs `--to` and one of `--from`/`--sid`/`--pane` (`:1178`); `--to auto` is rejected as an unknown account (`:1179, 1157-1158`; the map holds no `auto`, MEASURED `grep -c -i auto lib/account-map.generated.sh` = 0) | shown as `hold:<d>`, or `wait:<d>` with `--until-idle` | table `PANE SID DISPOSITION IDLE CACHE ACTION` plus counts, or `{from,to,rows[11 fields]}` |
| `cc-lr move --from A --to B\|auto [--until-idle S] [--cold-only] [--slots W] [--wait S] [--dry-run]` (`cc-lr:1237-1377`) | plan rows with act `move` or `wait` | acts through the poller: plan.json, one 0600 intent per session, one batch request, kickstart (`:1311-1341`) | explicit, or `auto` = the same single pick as above (`:1270-1274`); router asked strictly before any write (`:1291-1304`), again at admit and at close (`lr-move-batch.sh:142-150, 236`) | held, or with `--until-idle` waits for two consecutive `move` reads of the shared census (`lr-move-worker.sh:99-117`) | table, `batch <id> queued`, then one line per session as results land inside `--wait` (default 600 s): `✓ pane sid8 MOVED — reason` / `· … NOTMOVED` / `✗ … FAILED` (`cc-lr:1194-1200, 1352`); rc 0 all moved and nothing held, 1, 2, 3 |
| `cc-lr move --status <batch> [--json]` | one batch | lists; every verdict re-derived from disk and ps (`cc-lr:1201-1234`, `lr-move-lib.sh:82`) | — | — | `PANE SID RECORDED NOW REASON` plus the summary line. MEASURED on batch `20261006T060534Z-next3-next2-64630`: 7 rows MOVED/MOVED, 2 held rows `pending` |
| `cc-lr recover <ref>` | one session; refuses teammate, ambiguous, not-limited | acts, detached | `--target`, default auto | not applicable | 3 lines |
| `cc-lr switch [--target A\|auto]` | this pane's own session | acts, foreground | auto = desk rule, tier 2 only | not applicable | `verdict=` line |
| `cc-lr switch --pane P \| --sid S --target A` | one other session | interactive subject goes to `cmd_move` (`cc-lr:912-919`); a background session stays on the drainer (`:948-952`) | explicit | skipped unless `--until-idle` | switch lines |
| `cc-lr upgrade (--all \| ref)` | idle sessions on an old binary or model | writes requests; one serial drainer | same account | skipped | `✓ · ✗` lines |
| `cc-lr accounts --limited` | the reconciler's limit facts per account | lists | — | — | MEASURED: next, next2, next3 listed; all 5 facts flagged `contradicted`; next2's 7d fact names first_sid 4ad354fc, a session moved onto next2 from next3 |
| `status`, `status --cohort`, `repair`, `repair-markers`, `cohort refire`, `move --abort`, `__route-check` | run store, cohorts, one bundle, stale markers | read, or write one request | — | — | — |

## 2. Overlap, and what is missing

Overlap:
- Three listers of "limited" on three predicates: `cc-find --limited` (transcript tail over registry rows), `cc-limited` (markers and parked records, "no copy holds a real turn after the death"), `cc-lr accounts --limited` (reconciler facts). `recover --limited` uses the first. READ.
- Three spellings of one idle census: `switch --from A --all-idle --dry-run`, `move --from A --to B --dry-run`, `plan --from A --to B`. All call `lr-upgrade.sh --switch-census` (`cc-lr:1074-1076`). READ.
- Two actuators for a healthy session: the legacy ask-it-to-move drainer (behind `CC_LR_SWITCH_LEGACY=on`) and the move lane. READ `cc-lr:860-874`.

Missing for the two-command surface:

| gap | receipt | tag |
|---|---|---|
| No fleet-wide list. `plan` requires a source and a target; nothing iterates accounts or decides which need rotating | `cc-lr:1178` | READ |
| No fleet-wide rotate. Without `--account` the idle half never runs | `cc-lr:484` | READ |
| Busy now is dropped. In the recorded run pane 8 (4e9949e0) was planned `hold:mid-turn` with `until_idle_s: 0`, then needed its own recovery at 06:20:45Z | `move/20261006T060534Z-next3-next2-64630/plan.json`; `fleet/one-20261006T062045Z-4e9949e0/results.tsv` | READ |
| Near the wall is invisible. The only rule is `weekly_pct >= 100` or `session_pct >= 100`; rc 1 ("headroom") does nothing | `cc-lr:436-437, 486-507` | READ |
| The session that runs the command is `hold:self` and stays on the capped account | `lr-upgrade.sh:84, 931`; `cc-lr:1101` | READ |
| One target per batch. The 7 idle sessions all went to next2, while the 4 limited ones, picked per session, went to next2, next2, next4, next4. `claude-accounts --place` (batch placement, movers of kind `limited\|idle`) exists and only the reconciler calls it | `plan.json`; `fleet/one-20261006T06*/results.tsv`; `bin/claude-accounts:4996-5001, 5107-5121`; `grep -- --place` hits only `lr_recon/` | READ |
| Two verdict channels: limited by mail and `cc-lr status <sid8>`; idle by `move --status <batch>`. No single per-invocation table | `cc-lr:475, 1336` | READ |
| The batch roll-up is wrong in production. `summary()` puts a `case` inside `$( )`; launchd runs the runner under /bin/bash 3.2, which cannot parse it. The recorded batch has `"verdicts":"none"` and the one mail read "done: no rows" for 7 MOVED | `lr-move-batch.sh:80-83`; `lr-reset-poller.sh:292`; `batch.log`, `summary.json`; repro `/bin/bash -c 'x="$(for f in a.json plan.json; do case "${f##*/}" in plan.json\|admit.json) continue ;; esac; echo "$f"; done \| sort)"'` gives a syntax error and rc 1 on 3.2.57, `[a.json]` on 5.3.15. The suite runs `bash "$LRD/lr-move-batch.sh"` (PATH bash 5.3) and asserts only `.status` and `.target_auth_after` (`tests/lr-move-concurrency.bats:64, 88, 105`) | MEASURED |
| `--until-idle` can restart a session that hit its limit while waiting, with no prompt. An api-error tail reads at rest (`lr-upgrade.sh:237`); the switch census has no limit check (`:937-954`; the upgrade census has one at `:633`); the limit hold exists only at plan time (`cc-lr:1113`); the worker promotes on two raw `move` reads (`lr-move-worker.sh:109-111`); the intent gate lets kind `limit` through (`lr-handoff.sh:680-690`); the worker passes `--no-prompt` (`:151`). No test covers it (`tests/lr-move-worker.bats` 11 and 12 only) | as cited | INFERRED |
| `move --sid <prefix>` has no ambiguity refusal. The census matches by prefix (`lr-upgrade.sh:922`), `cmd_move` never counts rows (`cc-lr:1281-1287`), and with no `--from` the match is fleet-wide. The same check exists for `switch --sid` (`cc-lr:907-911`). `tests/lr-move-plan.bats` test 12 covers one match only | as cited | READ |
| The skill text never names `cc-lr plan` or `cc-lr move`, and its switch section still describes the serial drainer typing a prompt | `grep -c -E 'cc-lr (move\|plan)' commands/limit-recover.md` = 0; `commands/limit-recover.md:785-807` | MEASURED |
| `--account` is a hardcoded 4-account `case`; the generated map already has `CC_ACCT_NAMES` | `cc-lr:406-423`; `lib/account-map.generated.sh:54` | READ |

## 3. Smallest surface change

One verb, so the list and the act share one selection function.

```
cc-lr rotate --list [--account A] [--at PCT] [--until-idle S] [--json]
cc-lr rotate (--all | --account A) [--at PCT] [--to B|auto] [--until-idle S] [--wait S]
```

- `--list` writes nothing and defaults to fleet-wide. The act form requires `--all` or `--account A`, the rule `switch` and `upgrade` already hold (`cc-lr:826-836, 1996-2000`).
- `--at PCT` defaults to 100, which is today's rule. Lower values are the operator's explicit "near the wall"; no predictor is added.
- `cc-lr recover --limited [--account A]` stays as the old spelling of `rotate --account A`.

Code paths, all existing:

| step | calls |
|---|---|
| accounts in scope | `cl_acct_name` (`cc-lr:415`) or `$CC_ACCT_NAMES` |
| need per account | `cl_acct_cap` (`cc-lr:426-440`), extended to print the percentage and compare to `--at` |
| sessions | ONE fleet census: `lr-upgrade.sh --switch-census` with no `--from` (already allowed, `lr-upgrade.sh:925`), then `cl_move_rows`' lane holds per row (`cc-lr:1092-1125`). A row whose last record is a limit error is `recover` on any account; the rest are listed only for accounts in need |
| target | limited: lr-fleet's own per-session pick. Idle and busy: `--to`, else `cl_switch_auto_target <source>` (`cc-lr:701-724`) |
| act, limited | the subshell loop at `cc-lr:457-471` (every refusal of `cmd_recover` unchanged) |
| act, idle and busy | per source account, `CL_MOVE_EXCL="$seen" cmd_move --from A --to T --until-idle S --wait 0`, the call at `cc-lr:502` with until-idle passed through, then one wait loop over the batch dirs (`cc-lr:1343-1363`) |

Per session, both forms print one row (format sketch: the first three rows use values from the recorded batch, the fourth is invented):

```
ACCT   PANE  SID       NEED            STATE                 ACT      TARGET  ACTION
next3  11    4ad354fc  limited         limited               recover  auto    lr-fleet --one, verdict by mail and below
next3  2     7f5deb68  weekly 100%     idle 19293s cold      move     next2   restart on next2 in this pane, no prompt
next3  8     4e9949e0  weekly 100%     busy:mid-turn         wait     next2   waits until idle (<= 3600s), then restarts
next3  23    …         weekly 100%     hold:self             hold     -       run in that pane: cc-lr switch --target next2
```

- Footer: counts per ACT, and the caps that bound the run, by name: `recover 2 at a time (LR_ONE_MAX_CONCURRENT) · move 4 at a time (LR_MOVE_SLOTS)`.
- The act form then prints one verdict line per session as it lands: the existing `cl_move_result_line` for move rows, and for recover rows the run's `verdict.txt` (present in 6 of 6 `fleet/one-20261006T06*` dirs, MEASURED `ls`) rather than mail alone.

Alternatives considered:
- Extend `plan` (no `--from` = fleet-wide) and keep `move`: rejected, `plan --from A` means "everything on A" whether or not A is capped, so one verb would carry two meanings.
- Flags only on `recover --limited` (`--dry-run`, `--until-idle`, fleet-wide idle half): the smallest diff, kept as the implementation; the name "recover" for a list of healthy idle sessions is why `rotate` fronts it.
- Drive the list from `cc-lr accounts --limited`: rejected, all 5 current facts are `contradicted`.
- Drive the limited half from `cc-limited`: rejected for the act, it includes dead sessions (resume, not rotation) and its predicate differs from the one `cmd_recover` refuses on.

## 4. Where each refusal lives

| refusal | list side | act side |
|---|---|---|
| teammate | `cc-find:147-149, 152` (class), `:207-212` (candidate set); `cc-limited:748`; `lr-upgrade.sh:935` (teammate), `:936` (lead with a live teammate); upgrade census `:621-629` | `cc-lr:542-545` (recover, the only guard before `lr-fleet --one`); lr-handoff precheck `HELD:team` (`lr-handoff.sh:1342-1368`, names frozen at `lr-fleet.sh:1011-1013`) |
| ambiguous ref | `cc-find:275-280` (tuple tie), `:307-310` (sid prefix), `:331` (keyword); `cc-limited:1253-1255` | `cc-lr:384-387, 393-397` (`cl_resolve`); `:907-911` (`switch --sid`); `:2015-2019` (upgrade); `:1860-1864` (repair-markers); `:2168` (cohort); `lr-fleet.sh:64`. Absent on `move --sid` and `plan --sid` |
| not limited | `cc-find:150-157`; inverse hold `cc-lr:1113-1116` (`hold:limited`, `hold:api-error-<kind>`); `lr-upgrade.sh:255, 633` | `cc-lr:546-549` into `cl_refuse_not_limited` (`:343-377`); `lr-handoff.sh:690-694` |
| duplicate | `lr-upgrade.sh:570-572`, `:622`, `:934`; `:995` (`bg-split`); `cc-limited:766-767`; `lr-fleet.sh:256` | verdict conjunct P5, one holder (`lr-move-lib.sh:137`); a duplicate sid reaching `recover --limited` is refused as ambiguous by `cl_resolve` |
| mid-turn | `lr-upgrade.sh:223-246` (`lru_at_rest`), `:941-945`; `cc-lr:1095-1097` | wait rows: `lr-move-worker.sh:99-117`; move rows: lr-handoff precheck `HELD:busy` (`lr-handoff.sh:1342-1368`), reported NOTMOVED at `lr-move-worker.sh:173-174` |
| real draft in the composer | `lr-upgrade.sh:524-535` (rc 1 draft, rc 3 rail junk), `:953` (both hold for a switch), `:644`; `cc-lr:1098` (`hold:draft`) | lr-handoff precheck `HELD:draft`; `lr-fleet.sh:1015-1024` (snapshot and page) |
| one actuator per session | `cc-lr:1109-1118` (`hold:in-flight`) | `lr-lib.sh:657` (`lr_claim_take`); `cc-lr:302-313`, `:559` (recover), `:1513` (switch self); `lr-move-batch.sh:163-168` (`claim-held`); `lr-move-worker.sh:79-84` (`claim-lost`), `:88-92` (fence); `cc-lr:267-281`; `lr-upgrade.sh:1140` |

Further holds a rotate-all meets: `hold:self`, `hold:goal-live` (`cc-lr:1119-1121`), `hold:retired-source` (`:1099`), `hold:bg-session` (`:1100`), `HELD:bg-work` (recorded twice on 4ad354fc before its third attempt recovered), `HELD:no-shell`, `HELD:wake-guard` (`lr-handoff.sh:1377, 1508`).

## Uncertainties

- The until-idle hole is read from source, not reproduced. A later `recover` on that sid may nudge it in place (`lr-fleet.sh:1076-1078`), which would soften the outcome; nothing in the move lane triggers that.
- `cc-find --limited` lists registry rows whose process is dead, and `cmd_recover` does not check the liveness column (`cc-lr:534, 598`). What `lr-fleet --one` does with such a row was not traced.
- The census cost for a fleet-wide list is unmeasured here. The only figures are a source comment ("a census is ~7 CPU-seconds", `lr-move-worker.sh:97`) and the 17.7 s `cc-find --limited` run under load.
- Whether `claude-accounts --json` sweeps the network was not read, so the current percentages per account are not reported.
- Who fired the 06:03-06:07Z recoveries is not settled: their logs say "daemon-run: lr-reset-poller request drain", so the count of operator invocations for next3 is unknown.
- Live population at 06:41Z: 15 live registry rows of 30 files (12 on next2, 2 on next4, 1 on next, 0 on next3), MEASURED by `jq` plus `ps -p`. A next2 wall would put 12 sessions through a width-4 lane; the wall time for that is not estimated here.
