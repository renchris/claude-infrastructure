# A multi-pid `ps -p a,b` without `-x` can hang indefinitely

**Rule.** Every `ps … -p <comma-separated list>` passes `-x` and runs under a bound. A single-pid
`-p "$pid"` read needs neither change.

## Incident (2026-10-25, Darwin 24.6.0)

- `/bin/ps -o pid= -p 80493,67281` hung (a `timeout 8` returned rc 124). Dead pids made no
  difference. The same read was instant with one pid, as `/bin/ps -A -o pid=,lstart=`, or as
  `/bin/ps -x -o pid= -p a,b`.
- Probing all 2,018 pids one at a time found no culprit pid, so the hang belongs to the multi-pid
  path itself, not to any one process.
- Twelve such calls hung across the machine. Each one wedged a `handoff-fire.sh` launch for more
  than 50 minutes. Its census runs `bin/cc-sessions`, whose single bulk
  `ps -o pid=,lstart= -p <all registry pids>` read was the hung call. Killing the hung `ps` let the
  fire continue.
- The 13:16 reboot cleared it, so the fault is intermittent: the same command passing now proves
  nothing.

## Fix

- `bin/cc-sessions` bulk read: adds `-x`. The read already ran under `timeout`
  (`CC_SESSIONS_PS_TIMEOUT`, default 15 s), which falls back to the per-row reads and `kill -0`.
  The bound alone still cost every census its full timeout and then one `ps` per row; `-x` removes
  the hang itself.
- `scripts/convoy-gauge.sh` thread read (`ps -M -p <lsd,trustd,secd,tccd>`): adds `-x`.

## Tests

- `tests/cc-sessions-census.bats` "multi-pid ps…": a PATH `ps` stub hangs whenever it gets a
  multi-pid `-p` list without `-x`. The test asserts the census passes `-x`, never trips the hang,
  and settles every row from one `ps`. It is red on ba9e991dc, which hung to the timeout and then
  made 3 per-row calls.
- `tests/convoy-gauge.bats`: its `ps` stub now refuses a multi-pid `-M -p` without `-x`; dropping
  the flag reddens 26 of its 34 tests.
