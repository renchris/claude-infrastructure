# I1: account-attribution inventory (which code infers "the account a session bills" from its config dir)

Slot I1-account-attribution-inventory, 2026-10-25. This was a read-only `grep`/`sed` pass over
`bin/ scripts/ hooks/ lib/ statusline.sh mods/` in this worktree (commit bfe8025ff). `docs/` and `tests/`
were excluded, except that the tests pinning today's behaviour are listed in section 10. No file was
edited except this one. No ps, keychain, claude, or pane action was taken.

**Scope numbers (measured):**
- 317 files match `CLAUDE_CONFIG_DIR|claude-next|claude-secondary|claude-tertiary|claude-quaternary|config_dir|cfg_to_acct|acct_of|account_of|cc-registry|accounts\.json`. Command: `grep -rlE … bin scripts hooks lib mods statusline.sh core tools bus autonomy launchd | wc -l`.
- Most of those hits are the path-ladder idiom `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts|bin|hooks|lib/…"`. That idiom only locates a file and does not attribute an account, so it is left out of the tables below.
- 180 test files touch one of the attribution helpers. Command: `grep -rlE '<helpers>' tests scripts/limit-recover/lr_recon/tests | wc -l`. Section 10 names the ones that pin the semantics.

## 0. Four meanings of "account", and the class tag used in every row

| tag | meaning | changes on a mid-turn re-bill? |
|---|---|---|
| **BILLING** | the account whose bearer is on `/v1/messages` right now. Limits, walls, burn, routing, "whose quota am I spending" all belong here. | **YES.** Must be read from the per-session broker record keyed by sid, and that record must be **time-aware** ("sid S billed A from t₀"), because transcripts and markers are read after the fact. |
| **STORE** | the launch config dir. It holds `projects/<slug>/<sid>.jsonl`, `sessions/<pid>.json`, teams and tasks, and it is the dir a `--resume` must use. | no. The transcript never leaves the launch dir under a re-bill. |
| **KEYCHAIN** | the processes that read or refresh `Claude Code-credentials-<sha(dir)>`. This set gates heal and relogin rotation races. | no for the sessions themselves. Per-session stores hold `refreshToken:null` (P4-P6), so they do not race a refresh. The **broker** that copies from the keychain becomes a new holder and must take the same heal lock. |
| **DISPLAY** | a label only. | It should show BILLING, and show the store too when the two differ. |

Most sites today use STORE as a proxy for BILLING. They are listed so a designer can split each one.
"Broker lookup" below means `billing_acct(sid[, at_ts])` from the proposed broker table.

---

## 1. Launcher

| path | lines | what it infers today | class | change needed if a broker billing record exists |
|---|---|---|---|---|
| lib/claude-launcher.zsh | 68-108 `_cc_route_config_dir` | It asks `claude-accounts --route interactive` for an account name and maps it to a config dir. The routed dir becomes both the billing account and the store. | BILLING+STORE | Split the two. Pick the billing account through the router, and pick the store separately (it may stay fixed). Write the initial broker row (pid/launch nonce, then sid at SessionStart) and inject `CLAUDE_SECURESTORAGE_CONFIG_DIR`. |
| lib/claude-launcher.zsh | 129-143 `_cc_record_launch` | Appends a route.jsonl `slot:"launch"` row with `acct`, as "which account the session was born on". | BILLING (birth) | Keep it as the birth record. The broker's history is the source of truth after birth. |
| lib/claude-launcher.zsh | 146-187 `_cc_charge_on_commit` | Runs `claude-accounts --assign <acct>`, a phantom charge against the routed account. | BILLING | Charge the billing account. Unchanged when billing = routed account at birth. |
| lib/claude-launcher.zsh | 251-286 router `claude()` | Treats `CLAUDE_CONFIG_DIR` set as "pinned". A resume never routes (256-258), because "account is launch-time identity". | STORE gate | A resume must keep its store, but it can now be given any billing account. Relax the "resume never routes" rule for billing only. |
| lib/claude-launcher.zsh | 290 `claude1` | Pins `~/.claude-next`. | STORE | none |
| lib/account-map.generated.sh (+ scripts/gen-account-map.sh) | 11-25 `cc_acct_dir_for_name`; 32-40 `cc_acct_launcher_for_name`; 43-51 `cc_acct_name_for_dir_basename` | The dir↔name SSOT. `cc_acct_name_for_dir_basename` is the **root of almost every cfg→account inference** below. | STORE map | Keep it as the store map. Add a sibling `cc_billing_acct_for_sid <sid> [ts]` that reads the broker and falls back to the store map only when the broker is off (kill switch). Every caller tagged BILLING switches to it. |
| lib/config-mirror.zsh | 4-48 `_CC_ISOLATE` | `projects/`, `sessions/` and `.credentials.json` are isolated per account dir, so the transcript and the CC session row live in the launch store. | STORE (explains) | No change. This is why "the projects/ dir that holds the transcript" stops naming the billing account. |

## 2. claude-accounts (bin/claude-accounts, 13,239 lines, measured by `wc -l`)

| lines | what it infers | class | change needed |
|---|---|---|---|
| 733-805 `concurrency()`; 832-873 `_ps_census`; **875-962 `_census_from_lines`** | Counts the live claude processes per account. The account comes from the **LAST `CLAUDE_CONFIG_DIR=` in `ps -wwEo` env** (921-926). A bare or `~/.claude` process counts as `next` (888-896). The function returns `counts`, `headless`, `live_sids` (pid→sid via registry/argv, 943-958) and `unknown`. | BILLING proxy (and KEYCHAIN) | Split into two outputs. `k_billing[acct]` comes from joining each live pid→sid (already computed as `live_sids`) to the broker. `k_store[acct]` keeps today's env attribution for the heal gate. A pid with no sid (`unknown`) stays charged to its store account. |
| 967-1010 `_registered_sessions` / `_registry_entries` | Reads `<config_dir>/sessions/<pid>.json` → {pid: sid}, keyed per account dir. | STORE (sid join) | No change. This is the join that makes a broker lookup possible. |
| 1134-1240 `_native_census` / `native_census` | Same classifier (`_census_from_lines`) over KERN_PROCARGS2, with the same `by_dir` map (1165-1170). | BILLING proxy | Same split as above. |
| 807-826 `gate_counts` / `gate_census` | Heal's `k_live`: max(ps, native) per account. | KEYCHAIN | Keep the env/store attribution. Exclude processes whose env carries `CLAUDE_SECURESTORAGE_CONFIG_DIR` (they hold no refresh token). Count the broker as a holder through the shared heal lock. |
| 1936-1975 `heal()` | Refuses when `k_live > 0` and re-checks under `/tmp/claude-accounts-heal-<acct>.lock` (1952). | KEYCHAIN | The broker refresh/copy path must take the same lock (see handoff-fire 548-551). Otherwise unchanged. |
| 1529-1680 `working_concurrency` (k_work) | Walks `<config_dir>/projects/**.jsonl` written in the window and attributes each one to the **projects dir's** account (1562-1566). Also returns `sids` and `subs` per account. | BILLING | Attribute each fresh transcript (and each subagent transcript, through its parent sid) to `billing_acct(sid, mtime)`. |
| 3220-3336 `collect()` | Builds `row["k"]`, `k_work`, `k_sids`/`k_sids_at` (3315-3320), `k_native` (3327) and `bound_kwork` (3331) per account. | BILLING | Feed it the billing-attributed counts. No logic change. |
| 4204-4280 `bound_kwork`, `k_eff`; 4280-4402 `k_panes`, `_k_native_pick`; 4405 `k_cap`; 6261-6333 `_excluded` (`kmax-concurrency`) | Per-account routing and exclusion from the counts above. | BILLING (consumer) | No change. The inputs change. |
| 4467-4560 `_assignment_rows`, `assignment_counts`, `_live_assignments` | Phantom charges per account. The `sweep` drops a row whose sid the **same account's** `k_sids` already counted (4506-4547). | BILLING | Use billing-attributed `k_sids`. Otherwise a re-billed session is charged twice: once as a phantom on the target, once in the live count on the store. |
| 2877-2910 `inherit_k`; 8755 `get_data`; `--route/--rank/--readout` | Consumers of the per-account k. The readout's "live" column is `k`. | DISPLAY/consumer | None, because the inputs change. |

## 3. limit-recover / lr_recon (scripts/limit-recover/lr_recon/)

| path | lines | what it infers | class | change needed |
|---|---|---|---|---|
| observe_rows.py | 19-26 `CFG_DIRS`; 99-112 `acct_cfg_map`; **115-125 `acct_of_cfg`**; 128-136 `registry_cfg` (cc-registry `.account` → cfg); 155-186 `read_session_rows` (`<cfg>/sessions/*.json` → (cfg,row)) | config dir → folded account name; registry account string → cfg | STORE | Keep for the store. Add `billing_of(sid, ts)`. |
| observe.py | **866-986 `_sessions`**; 941-944 registry source cfg; 956 `cfg = lead holder cfg`; **969-970 `acct=acct_of_cfg(cfg, amap)`**; 983 `transcript_fn(obs.cfg …)` | `SessionObs.acct` is derived from the cfg of the process that holds the session row. | BILLING proxy | Add `SessionObs.billing_acct` (broker, keyed by sid). Keep `cfg` and `acct` as the store (transcript lookup and resume). Every limit/placement consumer below reads `billing_acct`. |
| types.py | 628 `SessionObs.acct`; 796/806 `Record.source_cfg/target_cfg`; 905 holds | data model | — | Add `billing_acct` on `SessionObs`, and `source_billing`/`target_billing` on `Record` (or redefine `source_acct`/`target_acct` as billing and keep the `*_cfg` fields as store). |
| __main__.py | **306-358 `_facts`**: 313-325 move guards (`mv.target_acct == s.acct`); 326-338 `F.fact_from_death(s.acct …)`; 340-352 ok-turns `(s.acct, …)` → `F.contradict` | Writes **limit/auth facts against the store account**, and contradicts facts with turns credited to the store account. | **BILLING (critical)** | A wall hit while billing next3 from a next4 store would block next4 today. Use the fact account `billing_acct(sid, death_ts)` and the turn account `billing_acct(sid, last_assistant_ok_at)`. |
| __main__.py | 279-303 `_amap`/`_cfg_of`; 402-455 stores/amap into census; 499, 531 cohort ids | accounts.json name→cfg | STORE | none |
| __main__.py | 645-680 stranded-tombstone page labels `acct_of_cfg(h.cfg)` | label | DISPLAY | Show the billing account, plus the store. |
| __main__.py | 1402 `settle_same_cfg(bound[0].cfg, rec.target_cfg)`; 1422 holds_amap; 1471; 2074 target transcript path | move success = holder or transcript under target cfg | STORE (relaunch moves) | A re-bill has no target cfg. Add a settle arm whose proof is the broker row plus the billed org seen on the next request. |
| census.py | 86-91 `_cover` → `F.blocking(facts, s.acct …)`; 107-170 `_binding`/`_mk(acct=s.acct)`; 174-256 `bucket`; 314-340 `cohort_id`/`cohorts_for` keyed on acct | which account's fact blocks this session; cohorts per account | BILLING | Use `billing_acct`. |
| census.py | 401-475 `new_record`/`upsert` (`source_acct=s.acct`, `source_cfg=s.cfg`, 464-473 re-home); 483-556 `not_needed_record`/`impossible_record`; 558-590 `_in_store`; 597-665 `successor_state`; 665-750 `stranded_tombstone`; 796-880 `stale_reconcile` (828 `req.raw.config_dir`; **835-848 NOT_NEEDED "live on <cfg> already"**) | source account = store; NOT_NEEDED when a live holder sits in a cfg other than the request's | BILLING+STORE | Set `source_acct` to billing and `source_cfg` to the store. NOT_NEEDED must compare billing to the target, not cfg to cfg. |
| plan.py | 153-165 `kwork` per `s.acct` | working sessions per account | BILLING | Use `billing_acct`. |
| plan.py | 174-190 accounts_json; 293-345 `holds_amap`/`with_holds` (`{acct: [cfg, store holds <sid>.jsonl]}`) | which store already holds the transcript | STORE | none |
| plan.py | 470-495 placement: stay if `p.acct == rec.source_acct`; `rec.target_cfg = cfg_of(p.acct)` | target account → target config dir (a relaunch) | BILLING+STORE | A re-bill keeps the cfg. The plan's action becomes "broker: sid → p.acct", and the stay test compares against the billing source. |
| act.py | 194-275 actuator argv (`source_cfg`, `target_cfg`); **342 `CLAUDE_CONFIG_DIR=` + rec.source_cfg** | the actuator runs under the source store | STORE | Add a new actuator kind `rebill` (a broker write). The relaunch path is unchanged. |
| evidence.py | 40 mirror fold; 60-75 holder classed target/source by `_same_cfg`; 164-166; 203; 258; 286; 352-374 transcript on target store | move proof keyed on the cfg | STORE | Re-bill proof comes from the broker log or the response's billed org, not from a cfg. |
| settle.py | 492; 531; 603; 700-760 (source/target swap after a move, 734); 985-1035 holder account label `acct = s.acct if same cfg else basename(h.cfg)`; 1295-1299 | settle by cfg; post-move source := target | STORE | A re-bill settles on the broker record. The post-move swap sets the billing source, not the cfg. |
| facts.py | 227 `_rows_for(wire, acct)`; 269-380 contradiction/blocking keyed `fact.acct` | facts are per account | BILLING (keys) | Keys stay account names. The writers above must pass billing. |
| drain.py / admit.py | drain 43-56 latch per acct; admit 687-705 pacer per acct | per-account pacing | BILLING (consumer) | Inputs only. |
| report.py | 327, 880-911 cohort/target acct | label | DISPLAY | Show billing. |

## 4. limit-recover shell scripts (scripts/limit-recover/)

| path | lines | what it infers | class | change needed |
|---|---|---|---|---|
| lr-lib.sh | 26-40 `lr_config_dirs` | store enumeration (mirror-deduped) | STORE | none |
| lr-lib.sh | 334-395 `lr_registry_live_rows` (sid → pane, pid, **acct**, cwd from cc-registry); 398-425 `lr_registry_live_rows_in_cfg` (row acct == cfg basename) | registry `.account` = store | STORE | Keep for "is the successor in this store". Do not use it as billing. |
| lr-lib.sh | 1030-1060 husk derivation (row acct vs `here` store) | store compare | STORE | none |
| lr-lib.sh | **1111-1127 `lr_pid_cfg`** (`ps -E` LAST `CLAUDE_CONFIG_DIR`); 1155-1200 `lr_successor_state` ("who carries a moved session now, keyed on the ACCOUNT each live holder RUNS UNDER") | process env → account | BILLING proxy | After a re-bill the same pid in the same store is the carrier, so this answers "not moved". Add a broker check: moved = `billing_acct(sid) != source`. |
| lr-lib.sh | 1209 `lr_source_dead <acct>` | is this account rejected (fact ledger) | BILLING (consumer) | Callers must pass billing (see handoff-fire 3403-3456). |
| lr-fleet.sh | **135-147 `lf_acct_of_cfg`** (map, then session-store realpath, then basename) | cfg → account | STORE map | Keep it. Add a billing variant. |
| lr-fleet.sh | 255-300 locate census: `acct=lf_acct_of_cfg(cfg)` for each limit-blocked transcript; 290 TRANSPLANTED label | the account a blocked session walled on = the store holding its transcript | BILLING | Use `billing_acct(sid, ts of the limit line)`. |
| lr-fleet.sh | 684-697 `_lf_target_holds_sid` | the target store already holds the sid | STORE | none |
| lr-fleet.sh | 753; 777 `lf_pick_target`; 808; 844 (exclude source account) | target ≠ source account | BILLING | The source is the billing account. The store is irrelevant to a re-bill. |
| lr-fleet.sh | 1175 `lf_acct_has_headroom`; 1240-1250 `lf_nudge hacct`; 1340, 1378 `tacct`; 1760-1860 `--one` (store glob → cfg → `lf_acct_of_cfg`, 1785-1806 `lr_pid_cfg` of the pane, 1855 headroom of the nudge target) | the headroom check and the nudge target read the store account | BILLING+STORE | Use billing for headroom and source. Keep the store for the relaunch dir. |
| lr-fleet.sh | 2027-2140 retire-husks (successor "under $(lf_acct_of_cfg $tgt)") | label/store | STORE | none |
| lr-reset-poller.sh | 706-717 `acct_of_cfg` | cfg basename → name | STORE map | Add a billing variant. |
| lr-reset-poller.sh | 1785-1791 request account fallback = transcript store | which account a request died on | BILLING | Prefer the hook's account (now billing), then `billing_acct(sid, ts)`. |
| lr-reset-poller.sh | **2348-2351+ transcript walk**: parks `(acct, weekly)` by **store**; 2472-2490 handoff-tombstone dating ("every limit event at or before the move is the source's") | park key = store account | BILLING (time-aware) | Park on `billing_acct(sid, event_ts)`. The tombstone-dating trick is exactly the time-aware broker history, generalised. |
| lr-move-lib.sh | 26-35 store fold; 52-60; **69-71 `lr_move_pid_cfg`** (`ps -E`); 103 P2 "started with CLAUDE_CONFIG_DIR == target, byte-exact"; 125 registry | the no-fork guard is keyed on the process env | STORE | A re-bill needs no P2. Its guard is "one broker row per sid". |
| lr-move-worker.sh | 55 `SRC_CFG=row config_dir`, `TO_CFG=.to_config_dir`; 277, 468 registry socket | the plan names a config dir | STORE | The re-bill plan carries `to_account`. |
| lr-move-batch.sh | 68 `TO_CFG`; 316 verdict cfg; 372 guard runs `CLAUDE_CONFIG_DIR="$TO_CFG"` | same | STORE | same |
| lr-select.py | 75-100 stores (name, basename); 166-174 registry | store list | STORE | none |
| lr-handoff.sh | 240 `CFG=${CLAUDE_CONFIG_DIR:-…}`; **632-638 evidence: fact account must == `cc_acct_name_for_dir_basename(CFG)`**; 653-658 intent source; 762-766 `LRH_FROM_ACCT` (verdict `from=`) | source account = this process's cfg | BILLING | Source account = `billing_acct(SID)`. Otherwise a re-billed session's own wall fact is refused as "account mismatch". |
| lr-upgrade.sh | 568 `lru_cfg_of`; 696-740 registry → acct, cfg; 873-900 `lru_bg_sessions` acct from cfg; 1002-1012 `lru_acct_name`; 1028-1035 `lru_store_acct`; **1054-1165 `--switch-census`**: `--from` filter (1078-1079, 1131) and **`on-target` disposition (1084, 1156)** by registry `.account` | which sessions are "on account A", and which are already on the target | BILLING | This feeds `cc-lr switch/move`. With "move all to next4", a session launched in next4 but billed elsewhere reads as on-target and is skipped. Use the billing account. |
| lr-ingest-verify.sh | 307-326 C1 `CLAUDE_CONFIG_DIR == manifest target_cfg`; 577-581 `SRC_ACCT` | transplant target identity | STORE | Relaunch path only. A re-bill does not run it. |
| lr-fire-resume.sh | 393, 412 target store → acct | store | STORE | none |
| lr-unstrand.sh 52-65; lr-transplant.sh 959-971; lr-lock.py 623-626, 956; lr-audit.py 1274-1821 | store enumeration, tasks/teams/transcripts | STORE | none |

## 5. cc-lr (bin/cc-lr)

| lines | what it infers | class | change needed |
|---|---|---|---|
| 270-286 `cl_recon_queue` | Writes `config_dir` into the recon request. | STORE | Also write the billing account at request time. |
| 506-522 `cl_acct_dirs` / `cl_acct_name`; 563 `recover --limited <acct>` selects sessions **by store dirs**; 604; 1839 dir→acct; 1944 `rotate` per account | "the sessions on account N" = the sessions whose store is N | BILLING | Select by billing account. |
| **781-790 `cl_from_acct`** (`CLAUDE_CONFIG_DIR` basename → name); 801 verdict `from=`; 830-842 source dropped from candidates by name | the caller's own account | BILLING | Use `billing_acct($CLAUDE_CODE_SESSION_ID)`. |
| 960-1116 `cmd_switch` (census via `lr-upgrade.sh --switch-census`, 1028-1030; `on-target` 1050-1068); 984-990 target validation | per-account selection | BILLING | Comes from the lr-upgrade change above. |
| 1254-1283 `cl_move_list_census`, TSV `pane sid account config_dir … act` | act `none` = on target | BILLING | Same. |

## 6. handoff-fire (scripts/handoff-fire.sh, 21,855 lines, measured by `wc -l`)

| lines | what it infers | class | change needed |
|---|---|---|---|
| 491 `CC_PROJECTS_DIRS` | store list | STORE | none |
| 548-551 `CC_HEAL_LOCK_PREFIX` (shared with claude-accounts heal) | keychain lock | KEYCHAIN | The broker must take the same lock. |
| 2830-2836 refusal label (acct from `RESUME_CFG`) | label | DISPLAY | billing |
| 3275-3350 `hf_account_evidence_check` (fact file account vs registry row account) | the fact applies to this pane's account | BILLING | Compare the fact with `billing_acct(sid, fact ts)`. |
| **3403-3419 `hf_tx_account`** (transcript path → account); 3420-3437 `hf_dead_source_notification`; 3448-3456 `hf_source_dead_for_tx` → `lr_source_dead(acct)` | "is the account this session is on rejected", which decides whether background work holds the session | BILLING | Use `billing_acct(sid)` (the limit line's ts for the notification case). |
| 4120 registry account; 4245-4256 `racct` label | label | DISPLAY | billing |
| 4707-4740 `hf_same_account_evidence` (registry `.account` == `--resume-cfg` basename) | same-store relaunch guard | STORE | none |
| 8293-8300 `rcy_acct_for_cfg`; 8321-8326 bg job `providerEnv.CLAUDE_CONFIG_DIR` | bg job store | STORE | none (S12: the bg supervisor is per config dir) |
| 13685-13830 `_sweep_keychain_account`, `pre_fire_account_sweep` | keychain item per account | KEYCHAIN | none |
| 14360-14385 PRP voluntary: registry row account → name vs fact | the pane's account for intent/evidence | BILLING | billing |
| **16738-16743 `cfg_dir` / `env_account`** (`CLAUDE_CONFIG_DIR` → name); **17355-17380** `ACCOUNT=$(env_account)` → `recycle_repick "$ACCOUNT"` (16745-17080) | the current account for the recycle re-pick ("is the current account excluded?") | BILLING+STORE | The exclusion test reads the billing account. With a broker, a re-pick becomes a re-bill with no `/exit`. The relaunch launcher still comes from the store. |
| 17383-17386 `proj_dir`/`activity` | **Counts transcripts written in the last 300 min per account's projects dir** (the fallback ranking). | BILLING | Count per billing account. |
| 11176-11201 cloud gate; 17397-17420 `ranked_accounts` | router consumers | consumer | none |

## 7. Hooks

| path | lines | what it infers | class | change needed |
|---|---|---|---|---|
| hooks/session-register.sh | **223** `acct=basename(CLAUDE_CONFIG_DIR)` minus the leading dot; 365-375 writes cc-registry `{…, account, pid, sessionId}` | **The root writer of the registry `.account`** that lr-lib, lr-upgrade, handoff-fire, cc-queue, cc-sessions, operator-readout, boot-resume and cc-limited read. | STORE | Keep `.account` as the store. Readers that mean billing join the broker by `sessionId`. Do **not** copy billing into this row: it would go stale on the next re-bill. |
| bin/cc-reconcile | 229-259 | The second registry writer (heals/backfills rows from the process env `CLAUDE_CONFIG_DIR`). | STORE | same |
| hooks/stop-failure-marker.sh | **118-139** `ACCOUNT` from `CLAUDE_CONFIG_DIR` via accounts.json/aliases; 205 cause key; 268-280 page; 515-525 request row `account`; **626 `facts hook-write --acct "$ACCOUNT"`**; 653-656 marker `{account, config_dir}` | **The account that hit a StopFailure (rate_limit/auth).** It writes the lr_recon limit fact directly. | **BILLING (critical)** | `ACCOUNT = billing_acct($SID, now)`. Keep `config_dir` as the store. Otherwise the wall lands on the store account and blocks it. |
| hooks/lead-crash-watchdog.sh | 1609-1620 `pane_launcher_for_cfg`; 1750-1760 `pane_acct_for_cfg`; 1838-1846 request `{config_dir, account}`; 1928 launcher | relaunch launcher (store); request account | STORE + BILLING (request) | Launcher from the store. Request `account` from billing. |
| hooks/handed-off-session-guard.sh | 162-176 `hog_acct` (store compare `ME` vs target) | same-store guard | STORE | none |
| hooks/subagent-long-bash-shadow.sh | 97 `_acct` in a log row | label | DISPLAY | billing (low) |
| hooks/session-start-dispatch.sh | 249 `CFG` basename | log label | DISPLAY | low |
| hooks/operator-readout.sh | 684 shows registry `.account` | label | DISPLAY | billing |
| hooks/boundary-handoff.sh | 412, 518 pass `CLAUDE_CONFIG_DIR` to the handoff | store | STORE | none |
| hooks/waiting-recycle.sh 254-264; hooks/lib/continue-sentinel.sh 24-31; session-continue.sh 20-22 | state keyed by cfg | STORE | none |
| hooks/lib/engagement.sh | 78-94 searches every home | account-agnostic | — | none |

## 8. Statusline / readouts

| path | lines | what it infers | class | change needed |
|---|---|---|---|---|
| statusline.sh | 228-231 `_cfg = transcript_path prefix before /projects/`, else `CLAUDE_CONFIG_DIR`; 277-293 writes `/tmp/cc-telemetry/<sid>.json` `config_dir` ("the cc-context×claude-accounts quota-join key", 203) | the quota-join key = store | BILLING (join key) | Add a `billing_account` field: the statusline reads the broker row by sid on each render (one small file read). Keep `config_dir`. |
| statusline.sh | **513-560** ordinal `NIDX` from the transcript cfg (`.claude-next`→1 … `.claude-quaternary`→4); 586-618 glyph render. The comment at 536-548 says it exists so the operator can see "whose quota he is spending". | DISPLAY (billing intent) | Render the billing account, as `4→3` when the store differs. |
| bin/cc-context | 59-62 `map_acct`; 110-120 telemetry `config_dir` → acct → `claude-accounts --json` quota | per-session quota | BILLING | Use telemetry `billing_account`. |
| bin/cc-board | 38-45, 54-57 `qrow(acct)`; 134-142 `config_dir` → acct | per-session quota | BILLING | same |
| bin/cc-value | 123-126, 151-169 `config_dir` → acct | per-session account | BILLING | same |
| bin/cc-queue | 170-175, 244-252 `--group-by account` from registry `.account`, else `config_dir` | grouping | BILLING | join the broker |
| bin/cc-sessions | 444 shows `.account` | label | DISPLAY | billing |
| mods/accounts-readout | renders `claude-accounts --readout` (its "live" column = k) | none of its own | consumer | none |
| scripts/lead-supervisor.sh | 838, 1013 telemetry `config_dir` for transcript age | store | STORE | none |

## 9. Other

| path | lines | what it infers | class | change needed |
|---|---|---|---|---|
| bin/cc-relogin | 260-330 `live_sessions(config_dir)` (ps -E LAST `CLAUDE_CONFIG_DIR`, max with `k_native`) | relogin rotation gate | KEYCHAIN | Same as heal: exclude per-session-store processes and take the shared lock. |
| bin/cc-limited | 150-200 `load_accounts`/`acct_name`; 209-262 `acct_death` from the marker row's `config_dir`; 655-765 `acct_now` from the registry row; "moved" = `acct_now != acct_death` → TRANSPLANTED/AWAITING-ENGAGE | death account and current account, both from stores | BILLING | `acct_death = billing at the death ts` (the marker will carry it once stop-failure-marker changes). `acct_now = billing now`. A re-bill without a relaunch is otherwise invisible. |
| bin/cc-token-ledger | 77-104 `classify_path` (config_dir from the transcript path); 634; 707 | token spend per config dir | BILLING (time-aware) | Attribute each turn by `billing_acct(sid, turn ts)`. |
| bin/cc-quota-price | 205-225 `transcript_roots` (`DIR_TO_ACCT`) | price per account from the transcript root | BILLING (time-aware) | same |
| bin/cc-husk-sweep | 140-160 `launcher_for_dir`/`acct_for_dir`; 375; 564 | husk relaunch | STORE | none |
| bin/cc-resume-resolve | 82-91, 154, 225-231 | resume store | STORE | none |
| bin/cc-find | 121-136 | store | STORE | none |
| scripts/boot-resume.sh; scripts/boot-resume-launch.sh | 354, 666-737, 859; launch 86, 300-305 | relaunch on the registry account's dir | STORE | After a reboot relaunch, re-apply the billing account from the broker (re-inject `CLAUDE_SECURESTORAGE_CONFIG_DIR`). Otherwise the session silently reverts to its store's account. |
| bin/cc-config-slot; scripts/relogin-desharing-activate.sh | cc-config-slot 2-54 (keychain name = sha(config_dir), "slots") | per-class config slots (G6, never activated) | KEYCHAIN | Overlaps the broker. Reconcile or retire. |
| tools/auth/auth-timeseries.sh | 35, 136 (keychain per account, `NLIVE`) | keychain health | KEYCHAIN | none |
| bin/cc-notify | 719-739 cloud account → `CLAUDE_CONFIG_DIR` | cloud sessions | n/a | none |
| scripts/desk-recycle-invariant.sh | 166 cfg from env | store | STORE | none |

---

## 10. Reconciler census: callers of `read_ps` and the other ps reads (scripts/limit-recover/lr_recon)

| site | line | ps form | feeds |
|---|---|---|---|
| observe.py `read_ps` | 161-205 (180-182 `/bin/ps -axww -o pid=,ppid=,stat=,lstart=,args=`; 190-192 `/bin/ps -axo pid=,tty=`) via `_ps_read` 127-158, `ps_bound` 94-105 | full table | `Snapshot.procs` and `ttys` |
| **observe.py `observe()`** | **805** `snap.procs, ttys = read_ps(run, stats=stats)` (on failure, 807-811: degraded "ps" and return) | the only caller of read_ps | the whole pass |
| __main__.py pass | **2748-2754** `observe.observe(paths, ctx.home, transcript_fn=transcript.observe, …)`; 2762-2766 `untrusted`/`claude_count` | — | the gate before every decision |
| observe.py `read_ps_env` | 527-543 (`/bin/ps -E -ww -o pid=,command= -p …`), called from `env_rows` 655 | env block | KITTY_* pane binding (W14) |
| observe.py `kitty_band` | 586-610 (597 `/bin/ps -M -p`), called 678 | threads | kitty band |
| store.py `proc_lstart` | 621-640 (in-process first via `inproc_lstart` 589; ps fallback 637); callers __main__ 245, 3049; act.py 692; admit.py 932 | `ps -o lstart= -p` | identity of records and actuators |
| act.py | 809 `ps -o command= -p <pid>` | argv | actuator check |
| fence.py | 150 `ps -o <field>= -p <pid>` | one field | fence |
| `snap.procs` consumers | __main__ 2648-2655; act.py 449-500, 687, 712-721; census.py 59 (`live_members`); evidence.py 88; observe.py 639, 724, 813, 878, 991 (`claude_count`); settle.py 1174; telemetry.py 569-574; types.py 675 (`Snapshot.alive`) | — | — |

The census itself does **not** read `CLAUDE_CONFIG_DIR` from ps. Its account comes from `<cfg>/sessions/<pid>.json`
location (`read_session_rows`) and cc-registry `.account` (`registry_cfg`) → `acct_of_cfg`. So a ps-free
census (S07) and a broker billing join are independent changes. The re-bill change lands at observe.py:956-970.

## 11. Tests that pin today's config-dir = account behaviour

- tests/account-fact-derivation.bats 258 and 273: the live-count attribution (trailing slash; the LAST `CLAUDE_CONFIG_DIR` wins). 11 `CLAUDE_CONFIG_DIR=` fixtures (measured by `grep -c`).
- tests/cc-relogin.bats 355 and 363: LAST `CLAUDE_CONFIG_DIR`; a bare claude counts toward next. 8 fixtures (measured).
- tests/claude-accounts.bats 155-368: inherit_k/census contracts (consumers of the counts).
- tests/claude-accounts-kwork-live-bound.bats, claude-accounts-place.bats 661 (`config_dir` realpath trust), claude-accounts-stranded.bats, claude-accounts-fleet-pace.bats.
- tests/stop-failure-marker.bats 143 and 331: the account is resolved from the config dir, alias-aware. 6 fixtures (measured).
- tests/handoff-recycle-repick.bats 100-134 and 245: re-pick from the current `CLAUDE_CONFIG_DIR` account.
- tests/handoff-recycle-same-account.bats; tests/handoff-recycle-cross-account-engage.bats.
- tests/lr-switch-driver.bats 151 (A3: `--from` by account name; ON-TARGET), 621, 755.
- tests/claude-launcher-router.bats: "`CLAUDE_CONFIG_DIR` set ⇒ pinned".
- tests/cc-reconcile.bats: the registry `account` = cfg basename. 9 fixtures (measured).
- tests/lr-reset-poller.bats; tests/lr-move-plan.bats; tests/rig-move-lane.bats.
- lr_recon/tests/test_observe.py 449 and 470 (`test_account_fold`, session row through a symlinked dir); test_census.py 243 (source_cfg follows the observed session); test_main.py 235, 248, 1621 (cohorts per account); test_session_row_reuse.py; test_pane_bind_env.py.

## Caveats

- Line ranges were read with `grep -n` and `sed -n` on this worktree. A few multi-function ranges, such as `handoff-fire.sh` 16745-17080, are bounded at the next function header and not read in full.
- `core/`, `bus/`, `autonomy/`, and `launchd/` were included in the file count, but their hits were not inspected row by row. None surfaced in the targeted greps for `cc_acct_name_for_dir_basename`, `acct_of`, `.account`, or `config_dir` attribution.
