# The four doubtful staged c10 activations, settled on measurement (2026-09-30)

Backlog-master wave 2, group `c10-activation`, ticket 1. Four staged items were doubtful enough that
running them in the operator's c10 batch could have done harm or nothing. Each is settled below with
the measurement behind it. Two studies ran independently for three of the four (this session's
research agents, and a duplicate session that stood down and handed its files over); where both
exist they agree, and both are cited. Binary measured throughout: Claude Code **2.1.284**
(`~/.claude-284/…/claude.exe`), the one all live sessions run.

| Item | Row | Verdict | Conviction | Outcome |
|---|---|---|---|---|
| 0022 MITL decider, synchronous shadow | c335e43cb3af | **RETIRE** | 85% (two studies) | `migration-superseded-by` on 0022; row closed |
| `$defaults` in `autoMode.soft_deny` | b19974f7ba82 | **NO** to `$defaults`; named rules → 0048, held | 85% on NO; 75% on the named set | row closed on the NO; 0048 behind a yes/no decision |
| read-before-write shim | 504d0bc2fe50 | **KEEP, fixed** | 95% | shim mirrors 2.1.284; registration staged as 0047 |
| 0004 L1 death-watch | 4a4b97a2585e | **RETIRE** | 80–85% (two studies) | `migration-superseded-by` on 0004; producer retired; row closed |

## 0022 — MITL decider in synchronous shadow: RETIRE

Premise correction first: `defaultMode=auto` is older than 0022 (settings backups show `auto` from
2026-04-17), so it is not what superseded it. The numbers (parallel study, `/tmp/c10-settle/0022-mitl.md`,
dev sessions only, deduplicated by `tool_use` id):

| Metric | Value |
|---|---|
| Bash permission prompts reaching the dialog, 09-17..09-30 | 914 = 65.3/day |
| Bash tool calls, same window | 92,531 = 6,609/day (prompt rate 0.99%) |
| Calls that would reach the model consult | 29,533 = 2,110/day, capped at 400/day fleet-wide (cap hit 13 of 14 days) |
| Consult wall time (n=6, live hook, haiku-4-5) | p50 ≈ 8.7 s, max 11.6 s, blocking the Bash call |
| Tokens per consult | ~31K input (mostly cache-read), ~360 output |
| Daily cost at the cap | ~58 min of blocked agent time, ~12M input tokens |
| Shadow verdicts that fall on a call that actually prompted | ~2 of 400 a day (0.53%) |
| Readers of its output (`~/.claude/autonomy/mitl-decider/`) | none; the directory does not exist |

A synchronous shadow pays the full latency on every consult to label a population that almost never
prompts, and nothing reads the labels. If the question is revived, re-stage it as an async shadow
keyed on the calls that prompted, never on PreToolUse/Bash.

## soft_deny `$defaults`: NO; the named safety rules as 0048, held for the operator

Full report: this session's study (`/tmp/w2c10/soft-deny.md`, summarised here). Shipped defaults on
2.1.284: soft_deny 70, environment 21. Live: soft_deny 35, environment 7, identical in all five
settings files.

- `"$defaults"` only ADDS: the 70 shipped rules would sit beside our 35, including newer, 2–12× longer
  versions of the 26 shared titles. Over a 14-day replay (2026-09-17..30, 10,820 transcripts,
  249,076 tool calls; text match against each rule, hand-checked on samples) it adds an estimated
  **+7 to +14 classifier blocks a day** against today's 16.4 judged blocks (ledger
  `~/.claude/logs/permission-denied.jsonl`). About 80% come from **Interfere With Workloads**
  (~38 kill/pkill calls a day) and **Shared Scratch Sweep**. That runs directly against the
  fewer-prompts goal, and it would also take on every future default unreviewed (65 rules in August,
  70 now). **Ruled NO** — the row's question is answered.
- Seventeen shipped rules guard real risks here and almost never fire (about 1–2 extra blocks a day
  together): Secret-Store Writes, Credential Materialization, Instruction Poisoning (replaces our
  Memory Poisoning), Auto-Mode Bypass, Session Transcript Tampering, Tmux Self Drive, Unverifiable
  Deletion Target, Public Data-Sharing Upload, External Ingress Tunnel, Traffic Redirection,
  Sensitive-Source Provenance, Code That Leaks When Run, and the five Browser rules. They are staged
  verbatim as **0048** (`migrations/data/0048-soft-deny-named-rules.json`). Conviction 75%, because
  the block rates are text-match estimates and no classifier was re-run, and because it trades
  prompts for safety, which is the operator's value call. 0048 carries
  `# migration-batch-hold: decision <id>` and joins the batch only once that packet is actioned.
- The environment half (`$defaults` in `autoMode.environment`, row d26bf99b6e9a) is not in doubt and
  is staged as **0046**. Several shipped rules lean on the shipped environment's definitions
  ("Trusted repo", "Sensitive data"), so 0046 should run first either way.

## read-before-write: KEEP the shim, with its predicate replaced

The shim (`hooks/lib/read-before-write-parity.sh`) keyed on `tengu_velvet_mallet_<bucket>`. That
flag is gone: the string occurs 0 times in 2.1.260, 2.1.280 and 2.1.284 (4 in 2.1.220). 2.1.284's
Write/Edit `validateInput`:

```
guardSkipped = !readFileState(path) && !isIpynb(path) && !kNt(model) && readAutoAllowed(path)
kNt(m) = zr.has(m.replace(/\[1m\]$/i,""))
zr = {claude-opus-4-6, claude-haiku-4-5, claude-opus-4-5, claude-opus-4-1, claude-opus-4-0,
      claude-sonnet-4-5, claude-sonnet-4-0, claude-3-7-sonnet, claude-3-5-sonnet, claude-3-5-haiku}
```

Live probes, Write to an existing file the session never read:

| Model | Account / mode | Result |
|---|---|---|
| claude-sonnet-5-5 | tertiary, next (headless, cwd = target dir) | overwritten (2 of 2) |
| claude-opus-5-5 | next, quaternary, tertiary; also `--permission-mode auto` | overwritten (4 of 4) |
| claude-opus-5-5 | this interactive session, target OUTSIDE its read allow-list | refused natively |
| parallel study, hooks disabled | opus-5-5 ×3, sonnet-5-5 ×3, opus-5 ×2 | overwritten; haiku-4-5 and opus-4-6 refused |

So the guard is off for every model the fleet runs wherever a Read is auto-allowed, which with the
bare `"Read"` allow rule is nearly everywhere. The shim's flag lookup found no `opus_5_5` /
`sonnet_5_5` key and allowed: it was blind exactly where it mattered. A bucket rename cannot fix it,
because no flag is read any more. `rbw_guard_disabled` now mirrors `kNt()`, the entry point
`hooks/read-before-write-parity.sh` speaks the PreToolUse protocol, and **0047** registers it.
The read-auto-allowed term is not mirrored on purpose: where a read is not auto-allowed the binary
still refuses, and validateInput runs before PreToolUse hooks.

## 0004 — L1 death-watch: RETIRE

Both studies (`/tmp/w2c10/deathwatch.md`, `/tmp/c10-settle/deathwatch-l1.md`) reach RETIRE, and for
the same reason, which is not the one the plan assumed:

- **custody-deathwatch has never run in production.** All 1,635–1,710 autonomy-sweep calls since
  2026-09-16 logged `skipped-not-deployed`: the sweep invokes it by its resolved checkout path and its
  deployed-copy guard refuses that path. Fixed in the same wave: the deployed sweep now calls the
  deployed, unresolved path (commit "fix(autonomy-sweep): the deployed sweep invokes custody-deathwatch
  by its deployed path").
- **lead-supervisor already does L1's job.** Under launchd KeepAlive it watches the same live lead
  pids (30 of 30 on 2026-09-30) and catches a death in **28 s p50 / 227 s p95**, then checkpoints the
  worktree and pages. A crash-watchdog hook adds p50 15 s / p95 28 s on the paths it covers.
- **L1 would add only sub-second detection**, and its pages go to a `desk` recipient that does not
  exist. Its own wiring was also broken: 0004's oracle reads `watch.tsv`, the producer writes
  `watch-list`, nothing schedules the producer, no plist exists, and a dead pid would re-page every
  30 s with no latch.

0004 declares `migration-superseded-by`; `scripts/deathwatch-watchfile.sh` carries a RETIRED note
(kept on disk because a lint and its suite still name it).

## Also settled while building the batch

- **0017** is superseded by **0021**: the FileChanged arm and `*` dispatch are live, and the
  CwdChanged slot holds `cwd-changed.sh` by 0021's design, so 0017's verifier can never pass and a
  re-run would undo 0021.
- **0003** drives the `/web-setup` TUI in a real pane; it is held as `manual` and never batched.
- **0031** was retired on trunk by the ledger-retraction sweep (05d68350b).
- **The shared `~/.claude/settings.json` carried `"model": "claude-fable-5-1[1m]"`** (a `/model`
  echo from 2026-09-30 19:25). 0037 would have copied it to all four accounts. `cc-settings-parity`
  now drops it (`SHARED_DROP`).
- **`unit-gate.sh` latency** (0024 makes it PreToolUse[0] on every tool call): 80 calls each,
  timed outside the child process: Read p50 14.1 ms / p95 22.8 ms; Bash p50 15.2 ms / p95 21.2 ms.
  Under the 50 ms budget.
- **0029's cap hits** cannot be counted: `frontier-spawn-gate.sh` keeps only per-session counters in
  `$TMPDIR`, and the 15:26 reboot wiped them. Registering its Bash arm only enforces the existing
  `max_fable_spawns_per_session` ruling on the session-fire path.
