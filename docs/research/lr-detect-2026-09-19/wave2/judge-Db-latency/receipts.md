# judge-Db-latency — receipts (read-only, run 2026-09-19, load avg 50.7)

## Reproductions of Db's own claims (all HOLD)
- `python3 census-probe.py` x3 => real 0.24 / 0.20 / 0.20; stage_ms cumulative
  {accounts 0.1, markers 0.9, parked 1.3, registry+ps 39.5, transcript-index 117.9,
   resolve 131.2, kitty-ls 164.2}. Output = 2504 bytes / 22 sids (~114 B/sid).
- slug-directed probe reproduced: `22 sids x4 roots -> 43 copies in 10.7ms` vs
  `full index: 2240 paths in 95.5ms`. Db claimed 5.4ms/14 sids; scales, holds.
- ps choice DEFENDED (my refutation failed): `ps -eo pid=,lstart=` med 31.8 ms vs
  `ps -o pid=,lstart= -p <37 pids>` med 123.8 ms. Full-table is 4x CHEAPER on macOS.
- session-beat ancestor walk cost bounded: single-pid `ps -o comm= -p` med 4.7 ms,
  `ps -o ppid= -p` med 5.1 ms => walk <=12 levels ~120 ms worst, ~25 ms typical,
  inside the hook's 9.7 s slack. (Dc measured the whole beat at ~10 ms.) Resolves
  Db § 14 UNMEASURABLE #1 in Db's favour.

## Refutations
- `grep -c 'IDLE-AFTER-ERROR' design.md` => 0 ; `grep -c 'RESUMING' design.md` => 0.
- `ls ~/.claude/autonomy/stop-failure/` => authentication_failed__.claude.jsonl,
  rate_limit__next.jsonl, rate_limit__next3.jsonl, rate_limit__next4.jsonl.
  No network/server_error cause key => Db's enumerator cannot see a net-blocked session.
- lr-fleet.sh:520 `[ "$kind" = limit ] || continue`  (--enqueue gate, exact match)
- lr-fleet.sh:465 `IDLE-AFTER-ERROR|RESUME-IN-PLACE)` ; :470 `TEAMMATE|RESUMING|TRANSPLANTED*)`
- tests/lr-fleet.bats:244 (IDLE-AFTER-ERROR), :271 (kinds mix), :311 (enqueue refuses
  mixed net-last), :324 (REGISTRY HOLE => RESUMING w/ argv pid). Db § 11.1 test 13
  scopes parity to tests/lr-fleet.bats:55-96 only — excludes all four.
- `cat ~/.reso/limit-recover/parked/*.json` => {sid,acct,cfg,cwd,kind:"weekly",
  reset_at_utc,parked_at} — NO transcript_path (=> no slug) and a third kind vocabulary.
- lr-fleet.sh:436-450 comment confirms Db's exit-5 rationale verbatim ("a valid empty
  list at exit 0, which any consumer reads as no blocked sessions").
