# W7e — the recycle engage check pages "dead" over a session that is answering (2026-10-01)

Scope (frozen): the resume-mode engage check in `scripts/handoff-fire.sh` (`__recycle` watcher,
`resume_engaged` and the dead verdict after its loop) stops reporting `recycle-dead` for a
cross-account relaunch whose target transcript holds an assistant turn; an unreadable target
transcript yields "unknown", not dead (LIMIT_RECOVER_FLEET_V2 § W6, wave W7e).

## 1. Reproduction from the real artifacts

| | session 89bdedfa (pane 18) | session 8e18da3f (pane 33) |
|---|---|---|
| alarm | `~/.claude/handoff-alarms/alarm-20261001T203646Z-52940-4087.json` | `alarm-20261001T203715Z-1736-26520.json` |
| ledger row | `recycle-dead` 20:36:46Z, watcher 52940 started 20:32:12 | `recycle-dead` 20:37:15Z, watcher 1736 started 20:33:00 |
| move | `.claude-quaternary` → `.claude-tertiary` (MANIFEST `target_cfg`) | same |
| watcher read | `--resume-cfg "$TCFG"` (`lr-handoff.sh:1685`) = `/Users/chrisren/.claude-tertiary` | same |
| target transcript | `.claude-tertiary/projects/-Users-chrisren-Development--worktrees-film-held-daylight-brag-output-work-assets/89bdedfa-….jsonl` | `.claude-tertiary/projects/…/8e18da3f-….jsonl` |
| first real turn on target | 20:33:07.722Z (claude-opus-5-5, after a peer-mail task-notification at 20:32:52) | 20:33:49.862Z |
| launcher (`lr-fire-resume.log`) | 20:32:40 `✗ READY NEVER SEEN — prompt NOT typed` | 20:33:27 same |
| run token in transcript | 0 occurrences of `run:89bdedfa:20261001T203200Z:472508ec` | 0 of `run:8e18da3f:20261001T203237Z:5c661e2c` |

`resume_engaged` extracted from `handoff-fire.sh` and run against the live target files:

```
89bdedfa with-token rc=1   no-token rc=0
8e18da3f with-token rc=1   no-token rc=0
```

**The working hypothesis (wrong config dir / pre-transplant path / changed sid) is REFUTED.** The
watcher read the right file: target config dir, same sid. The mechanism is the TOKEN GATE. W3 made
the resume oracle answer only "did a turn follow a user record carrying this run's token"
(`resume_engaged` $4, "NO TOKEN RECORD ⇒ rc 1, DELIBERATELY"). When lr-fire-resume refuses to type the
prompt (READY-NOT-SEEN: the screen read UNKNOWN, and Enter on a parked menu takes its default), the
token can never arrive, so the oracle is rc 1 for the whole window by construction. The session
meanwhile resumes with its full transcript, wakes on peer mail and works. At 180 s the watcher
emits `recycle-dead` and pages "claude is alive at an empty composer, the continuation did NOT
start". That is false on every such run.

The third live record (pane 28, f8b54aee, 21:23:21Z) is the same shape: its target copy holds a real
turn at 21:19:09Z, 64 s after its watcher started.

## 2. Fix

Before the dead verdict, resume mode reads the target once more:

- **No readable `$cfg/projects/*/$sid.jsonl`** (or no target cfg at all): `recycle-unverified`,
  "unknown — could not read transcript …", no page, debt discharged (a claude is alive in the pane).
- **A token was handed over but the oracle never fired, and an untokened real turn after T0 exists
  on the target:** `recycle-engaged`, with the line and row naming the weaker proof ("ANSWERING …
  without the relaunch prompt", plus READY-NOT-SEEN when the launcher logged it).
- Otherwise the existing dead verdict stands.

The token stays the first proof: the new read runs only after the full window, so a session that
does take our prompt still reports through the token arm.

## 3. Replay over the existing alarms (read-only; no record edited)

The live store `~/.claude/handoff-alarms` holds 20 HANDOFF-RECYCLE-DEAD records (the SessionStart
count of 41 is every handoff-alarm class). Sixteen come from the timeout ("never engaged") arm this
change touches, and four from the other arms (pane gone, surface gone, never reached a shell, no-prompt),
which it leaves alone. For each of the 16, the replay took the target cfg and the sid from the bundle
`MANIFEST.json`, the token from the launcher, and T0 from the ledger row's `watcher_lstart`. Eleven
older rows have no `watcher_lstart`, so for those it used the bundle mint time; that is weaker but
still before the relaunch, and the session was limit-blocked in the gap. A real turn had to sit
between T0 and the alarm's own timestamp.

| verdict under the new check | count | records |
|---|---|---|
| ENGAGED | **12 / 16** | panes 683, 405, 513, 782 (09-26), 810, 812, 814, 819, 782 (09-27), 18, 33, 28 — 9 of the 12 on the bundle-time baseline |
| still dead | 4 / 16 | panes 751, 815, 1317, 1311 (no target turn before the alarm) |
| unknown | 0 | every target transcript was readable |

The 12 pages were false. The four left dead had no target turn when they fired.
