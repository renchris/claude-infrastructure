# CAPTURE-RECEIPT — cc-limited fixture

Captured **2026-09-20T14:18:22Z** (epoch 1789913902) by `tests/fixtures/lr-2026-09-19/capture.sh`.
Pinned instant `LR_NOW=2026-09-20T14:18:22Z`; every age, reset countdown and claim age below is
relative to it, never to a wall clock.

## What was copied, and from where

| store | source | items |
|---|---|---|
| markers | `/Users/chrisren/.claude/autonomy/stop-failure` | 7 file(s) |
| registry | `/Users/chrisren/.claude/cc-registry` | 62 row(s) |
| beats | `/Users/chrisren/.claude/cc-beats` | 3842 file(s) |
| state (locks/parked/results/requests/faults/fleet) | `/Users/chrisren/.reso/limit-recover` | see listing |
| accounts | `/Users/chrisren/.claude/accounts.json` | present |
| idl (tail 131072B) | `/Users/chrisren/.claude/autonomy/idl.jsonl` | present |
| transcript tails (131072B each) | `$HOME/.claude*/projects` | 43 copy/copies |
| ps table | `TZ=UTC LC_ALL=C ps -eo pid=,lstart=` | 1515 row(s) |

## Registry rows actually present AT CAPTURE

This is the list amendment #1 exists to make checkable. Any drill row asserting a registry
pane NOT in this list is hand-asserted and must be re-derived.

```
110 111 112 114 115 116 117 123 126 127 128 129 133 134 136 138 143 145 149 155 156 157 158 166 167 
172 174 175 177 178 186 196 198 201 214 215 218 260 261 262 263 264 265 286 287 329 330 331 332 334 
335 336 337 338 339 340 341 342 343 345 346 347 
```

## Sids the markers name

```
07e30aeb-bb48-4771-9e0d-feff40ceb4cf
0874804f-2521-4d79-b23c-1098234e021b
09e64dcb-16c7-4c65-8b11-fd854d50f299
0e2567ee-82fa-44d0-adb0-dd23c80413e6
11569d45-8a26-4bf0-a568-51efd70eff63
12e163a9-a64e-4e60-8029-5803e034ac7e
26cd14be-a7a4-422f-b568-cfd4609e0806
28f07827-d9de-41d5-a267-341ae7e05bad
4bc1159f-c644-4bf5-8fee-8f8714438fa6
540263da-d71a-4f6c-bb03-be8e864c087c
65186f1f-dcb2-4e3d-b53d-38145ba4aaf1
75c7e2a5-6387-400f-85ce-f1ff6386a001
7730a605-d982-4001-b2ba-18a6c2657259
7c81d279-587d-46f9-b549-3c4aaaea816d
7f533f05-91fa-42d0-89ef-cd7976c423d5
83c4f1b8-3a41-4a4f-b1d7-529e5de46ace
850f9626-76a0-42e6-9672-44418ecb2b83
8843bcf3-0fc7-484b-bcaa-628c09a9ebfb
98f02458-7842-4bc9-9040-f18846fa1f18
b11f0027-d940-4f50-b223-faa31cf91a62
c0f857b6-4965-4db8-816d-02d69b7a108e
c301b7a5-0133-4482-9f45-c7ce9b888c4d
cb227486-f06c-46f0-99d2-3e38af3c4f93
cb29ae36-b686-485c-be63-745a82542fe1
d02d8feb-1f9d-42bb-8487-80b726c88950
db18f6fd-381c-479d-a917-67783810c095
df12fe89-f002-4065-a250-ba10ceb9c973
e442434c-1a96-4c04-b06e-ac89c2f9891a
e9561f51-d476-4afd-90d8-efbc473e24de
eb77ca3e-c23c-4f1d-858f-4b116cd759d3
fff83638-1f50-4681-82c0-95b4702f8029
```

## The DERIVED expectation

`EXPECTED.screen` (exit 0) and `EXPECTED.tsv` (exit 0) were produced by running
the census against THIS snapshot at THIS instant. They are goldens, not assertions: a drill
re-runs the census over the same capture and diffs. Nothing here is quoted from § 5.

```
next    seven_day · resets 04:00:00Z (passed)      4 need attention
  RESET-PASSED                 df12fe89 ×1  err 22:57:38Z  claude-infrastructure  ← the reset has passed; nudge in place
  NO-PANE                      83c4f1b8 ×1  err 21:52:09Z  claude-infrastructure  ← no live process holds it
  DUPLICATE                    c301b7a5 ×1  err 21:48:22Z  claude-infrastructure  ← 2 live processes hold this session
  DUPLICATE                    c0f857b6 ×1  err 21:40:08Z  reso-web-app           ← 2 live processes hold this session
next2   - · no reset                       1 need attention
  IDLE-AFTER-ERROR             cb29ae36 ×1  err 23:35:18Z  claude-infrastructure  ← network death, pane alive; resume IN PLACE, never a transplant
next3   - · no reset                       1 need attention
  IDLE-AFTER-ERROR       #343  850f9626 ×1  err 10:29:21Z  wt-lr-detect-100p      ← network death, pane alive; resume IN PLACE, never a transplant
next3   five_hour · resets 21:30:00Z (passed)      8 need attention
  NO-PANE                      07e30aeb ×1  err 20:29:28Z  wt-cc-143039-68221     ← no live process holds it
  NO-PANE                      26cd14be ×1  err 20:04:34Z  claude-infrastructure  ← no live process holds it
  NO-PANE                      4bc1159f ×1  err 20:00:44Z  claude-infrastructure  ← no live process holds it
  NO-PANE                      8843bcf3 ×1  err 19:58:53Z  claude-infrastructure  ← no live process holds it
  NO-PANE                      65186f1f ×2  err 19:58:34Z  subagent-lifecycle-w0  ← no live process holds it
  NO-PANE                      98f02458 ×2  err 19:57:43Z  wt-pool-2              ← no live process holds it
  NO-PANE                      11569d45 ×3  err 19:53:50Z  claude-infrastructure  ← no live process holds it
  NO-PANE                      09e64dcb ×3  err 19:53:38Z  claude-infrastructure  ← no live process holds it
next4   - · no reset                       1 need attention
  IDLE-AFTER-ERROR       #339  540263da ×1  err 11:03:16Z  wt-lr-detect-100p      ← network death, pane alive; resume IN PLACE, never a transplant
next4   five_hour · resets 19:40:00Z (passed)      6 need attention
  CWD-GONE                     0e2567ee ×1  err 19:28:09Z  wt-cc-142549-10206     ← cwd is gone: /Users/chrisren/Development/.worktrees/wt-cc-142549-10206
  CWD-GONE                     fff83638 ×1  err 19:28:05Z  wt-cc-142546-79030     ← cwd is gone: /Users/chrisren/Development/.worktrees/wt-cc-142546-79030
  NO-PANE                      e442434c ×4  err 17:27:19Z  claude-infrastructure  ← no live process holds it
  NO-PANE                      28f07827 ×4  err 17:14:48Z  wt-cc-100046-36511     ← no live process holds it
  NO-PANE                      cb227486 ×1  err 17:07:16Z  claude-infrastructure  ← no live process holds it
  CWD-GONE                     d02d8feb ×1  err 16:59:19Z  wt-cc-095358-75429     ← cwd is gone: /Users/chrisren/Development/.worktrees/wt-cc-095358-75429
next4   seven_day · resets 09:00:00Z (passed)      5 need attention
  NO-PANE                      75c7e2a5 ×3  err 21:51:55Z  claude-infrastructure  ← no live process holds it
  NO-PANE                      7730a605 ×1  err 21:42:13Z  wt-d467a07fd274        ← no live process holds it
  RESUMING                     12e163a9 ×4  err 21:39:17Z  claude-infrastructure  ← a resume is in flight
  NO-PANE                      eb77ca3e ×3  err 21:37:05Z  wrap-ledger-resident-m ← no live process holds it
  NO-PANE                      7f533f05 ×11 err 21:35:53Z  wt-cc-143333-63422     ← no live process holds it
31 sessions · 60 marker rows · 0 unaddressable · enumerator ok · (-p sessions: run --deep)
```

---

## THE RULING amendment #1 demanded — row 1 of § 5 is `NO-PANE`, not `RECOVERABLE (stub)`

Amendment #1 (§ 11, FATAL, 92 %) left row 1 of the § 5 drill to be decided by the live capture,
under a rule it stated in advance: **no registry row ∧ no resume leaf ∧ beat pid dead ⇒ `NO-PANE`;
a live beat pid ⇒ `RECOVERABLE (stub)` via amendment #2.** All three arms were read off THIS
capture, and they agree:

| arm | read | source in this capture |
|---|---|---|
| registry row for `07e30aeb` | **absent** | the 62-pane list above — `147` is not in it, and no row anywhere carries that sid |
| resume leaf `--resume 07e30aeb` | **0** | `procs.txt` |
| beat pid alive | **dead** | `home/.claude/cc-beats/07e30aeb-….json` names `pid 84167`, which is absent from the 1,515-row `ps.txt` |

⇒ **Row 1's true state is `NO-PANE`**, and `EXPECTED.screen` above renders exactly that, derived
rather than asserted. § 5's `#147 RECOVERABLE (stub)` was a description of a moment, quoted as if
it were a standing fact.

**Where `#147` actually comes from, and it is the finding that makes the fabrication legible.**
The beat is not merely dead — it is the ONLY store that still knows this session ran in pane 147:

```json
{"sid": "07e30aeb-…", "pane": "147", "pid": 84167,
 "lstart": "Sat 19 Sep 19:32:08 2026", "cwd": "…/wt-cc-143039-68221", "seq": 3}
```

`build.sh:99` hand-wrote `reg 147 07e30aeb-… claude-tertiary 84167` — the same pane and the same
pid, in the same order. So the disputed registry row was **reconstructed from this beat**, not
measured from the registry. That is P5's pane-keyed-overwrite class seen from the other side: the
registry row was written and then overwritten by the next occupant of pane 147, while the beat,
which is sid-keyed, survived. It is also why amendment #2 makes the beat a second liveness source
— the registry's incompleteness is structural, not incidental.

**What this receipt does NOT license.** The capture is one instant. `EXPECTED.screen` is a golden
for THAT snapshot and nothing else; re-run `capture.sh` to get a fresh pair. A drill that quotes
these rows a week from now has repeated exactly the error amendment #1 was written to end.
