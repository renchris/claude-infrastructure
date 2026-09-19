# teammate-probe — the W5 scratch project

The controlled fixture for the two lifecycle probes in
`docs/research/subagent-lifecycle-2026-09-19/P-probes.md` (wave W5 of
`docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md`). It measures; it changes nothing.

## Safety, by construction

* Nothing here kills, closes or signals anything. There is no `kill`, no `it2 session close`, no
  `kitty @ close-window` in any file. The P1 lead is ended by typing `/exit` into **its own**
  composer — the vendor's graceful-exit path, which is the subject under test.
* Every census is a **set difference** against a pre-launch snapshot, so a sibling session's pane or
  member can never enter the result. See `P-probes.md` §0 for the three ways a naive census was
  measurably wrong on this box before this shape was arrived at.
* The fleet closer is held off with **its own documented switches** — `TEAMMATE_SHUTDOWN_DISABLED=1`
  in the probe lead's env (P1) and the `.teammate-busy` cooperative marker (P2). No fleet code and no
  committed config is modified, and `teammateMode` is never touched.

## Files

| file | what it is |
|---|---|
| `run-p1.sh` | the P1 runner and observer. `./run-p1.sh <label>` runs a probe; `./run-p1.sh --census` runs the instrument's own control |
| `lead-brief-p1.txt` | the P1 lead's prompt: spawn `probeA..probeD`, wait for all four idle, print a marker, then hold |
| `target.txt` | the only file a probe member ever reads |
| `.claude/settings.local.json` | the scratch project's own permissions |
| `captures/` | the raw evidence, committed — this is the report's substance |

## Re-running

```
cd tests/fixtures/teammate-probe
./run-p1.sh --census      # instrument control: prints 0 when no member of ours is live
./run-p1.sh myrun         # a full P1 run; blocks in preflight until the box is quiet
```

`run-p1.sh` **refuses to run on a busy box** (exit 3), and that refusal is the point. RC-10's subject
is a 2 000 ms wall-clock race, so a loaded box makes the vendor miss it for reasons that have nothing
to do with the vendor — and "survivors > 0" is the direction that licenses a fleet-side change. The
preflight needs `cc_sp_active <= 3` and CPU idle `>= 40%`; the same wait also clears the fleet's
admission gate (`hooks/agent-teams-enforce.sh` → `cc_capacity_admit`, ceiling 8 sessions mid-turn),
which refused 3/3 spawns on the first attempt. Tunables: `PROBE_MAX_ACTIVE`, `PROBE_MIN_IDLE_PCT`,
`PROBE_PREFLIGHT_WAIT_S`, `PROBE_IDLE_TIMEOUT_S`, `PROBE_SETTLE_S`.

**Do not "fix" the preflight by exporting `CC_ADMIT_GATE=off`.** That defeats a protective gate in
order to measure a race, and the measurement it buys is of a box in the state the gate exists to
prevent.

## P2 is not scripted, on purpose

P2 needs the `shutdown_request` to be *structurally* exact (`{"type":"shutdown_request",…}` through
`SendMessage`; a prose request does nothing on this runtime). That is the lead's tool call, so the
lead was the W5 session itself and the run is recorded in `captures/p2/` rather than driven from a
script here. `captures/p2/` holds the precondition, the T0/T+10 s/T+60 s pane captures, the member
transcript path and its tail, and both censuses.
