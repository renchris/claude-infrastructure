# desk self-recycle — GO-LIVE snippet (waiting-recycle Stage-2 deterministic fire)

Turns the desk's idle+high-context self-handoff from **advisory-only** (fires only if the model
notices + complies — 0/2419 in prod) into a **deterministic** fire: at a quiet monitoring boundary
the `waiting-recycle.sh` hook itself runs `handoff-fire.sh --recycle` after a grace window, with NO
agent or human decision in the loop. This is the crux of no-idle, no-HITL 24×7.

**C10 posture (why the agent performs this one, unlike a launchd/plist activation):** the two-stage
hook is **already installed** (PostToolUse:Bash in `~/.claude/settings.json` + `.claude-tertiary`,
merged to `main`, live via the `~/.claude` symlink). Going live installs **no new** hook, daemon, or
setting — it flips the hook's own per-cwd **opt-in sentinel** via the sanctioned CLI
(`waiting-recycle.sh arm --live`), which is exactly the desk's documented action. So the arm is
agent-performable; it does not need the operator wiring a plist. The operator's controls remain the
kill-switches below.

## The root cause this fixes (CFG-stranding — disk-verified 2026-07-19)

`waiting-recycle.sh arm` keys its sentinel by `shasum("$CLAUDE_CONFIG_DIR|$cwd")` under
`$CLAUDE_CONFIG_DIR/state/waiting-recycle`. An arm is therefore visible **only** to a desk running
under the **same** config dir. The desk migrates config dirs across a recycle (observed
`.claude-tertiary` → `.claude` in ~2 days) and its state dir can be wiped — either strands the arm
under a config **the live desk never checks**. A stranded arm makes the hook abstain `not-armed` on
every poll (**1309** such abstains observed, **0** shadow fires) — the mechanism silently decays to a
no-op, re-introducing the HITL dependency it exists to remove. A one-shot manual `arm` re-strands on
the next migration.

**Fix:** arm the desk cwd under **every** config root it may run under, via a re-runnable helper that
self-heals a wipe or a migration. Arming a `(cfg, cwd)` where no monitoring desk runs is inert — the
hook fires only for a session whose own `(cfg, cwd)` matches AND is a monitoring desk that trips the
trigger; a stray sentinel with no such session never fires.

## What was built (repo files, on `feat/desk-self-recycle-golive`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `scripts/desk-arm-live.sh` | the go-live actuator: resolves the desk cwd (the repo `~/.claude` symlinks from), arms `--live` with the canonical brief under every config root; `--shadow`/`--dry-run`/`--cwd`/`--brief` | **no** — a plain CLI; run it to go live (or re-run to self-heal) |
| `tests/desk-arm-live.bats` (7) | RED-proofs: multi-config LIVE arm, SHADOW omits the live file, dry-run inert, brief/cwd validation, **loop-breaker cooldown survives a re-arm**, symlink cwd-resolve | none (regression only) |
| `docs/templates/desk-boot-brief.md` | the Stage-2 successor prompt (already tracked) — seeds a never-task-less fire (FM-D) | none |
| `hooks/waiting-recycle.sh` | the two-stage hook (already merged + installed) | none |

## Go live (agent-performed; also the self-heal command)

```sh
# From a dedicated worktree after landing feat/desk-self-recycle-golive via the project-local /ship:
~/.claude/scripts/desk-arm-live.sh              # arms LIVE across ~/.claude + ~/.claude-tertiary
#   (repo path also works: scripts/desk-arm-live.sh — resolves waiting-recycle.sh beside it)
```

Idempotent and **successor-safe**: a re-arm of an already-armed cwd does **not** clear its
cross-generation cooldown (the CLI's `was_armed` guard), so re-running never defeats the loop-breaker.
Soak-first instead of straight to live: `desk-arm-live.sh --shadow` (logs would-fire, no exec).

## How the fire works + the landmines it respects

- **Two-stage:** Stage 1 advises `/handoff` and starts a `GRACE_S` (180s) clock; Stage 2 fires
  `handoff-fire.sh --recycle` itself if the desk is still fire-worthy after grace. The successor pane
  IS the continuation (frozen DoD + re-derive-from-disk brief).
- **Cap-trap:** Stage 2 is cap+cooldown **exempt** (bounded by a one-fire-per-SID latch) — a non-exempt
  Stage 2 would be permanently silenced by the 3-advisory cap.
- **Rot-floor:** a behavioral rot tell counts only with **fresh** telemetry AND `used_pct ≥ ROT_FLOOR`
  (25%). The shipped rot regex false-positives on healthy watch narration ("re-checking which sessions
  are running") at low fill; the floor is what makes the deterministic fire safe from that
  (bats #30/#31/#34 cover it). Do not lower `ROT_FLOOR` without re-proving those.
- **Blast radius of a wrong fire = one clean recycle**, not data loss: the fire path is the same
  `handoff-fire.sh --recycle` a manual `/handoff` uses; the successor re-derives from disk. The design
  biases false-negative (a missed recycle just waits for the next boundary).

## Verify (after arming)

```sh
# from the desk cwd, under the desk's config dir:
CLAUDE_CONFIG_DIR=~/.claude          waiting-recycle.sh status    # → ARMED · mode: LIVE · brief: … lines
CLAUDE_CONFIG_DIR=~/.claude-tertiary waiting-recycle.sh status    # (staged for a migration back)
grep -c '"disposition":"fired","reason"\?.*stage2-live' ~/.claude/autonomy/idl.jsonl   # live fires, once soaked
```

Note: **0 organic shadow fires** to date were a symptom of the stranding bug (the arm sat under a
config no live desk checked), **not** of the fire path — which is proven by `tests/waiting-recycle.bats`
(47) + `tests/desk-arm-live.bats` (7) + a sandboxed shadow→live harness run. Expect real `stage2-live`
records to begin appearing once an armed desk next crosses a quiet boundary.

## Rollback / kill-switches (operator controls, unchanged)

```sh
waiting-recycle.sh clear      # per-desk opt-OUT (run from the desk cwd; removes arm+live+brief+cooldown)
waiting-recycle.sh kill       # GLOBAL blanket off — no session recycles until `unkill`
desk-arm-live.sh --shadow     # soften LIVE → SHADOW (keeps advising, stops the exec)
```

`clear` is the immediate per-desk switch; `kill` is the machine-wide switch; `--shadow` damps without
disarming. None require touching the hook, settings, or a daemon.

## Deferred (net-positive, beyond this go-live — operator's call)

- **F3 auto-arm-at-spawn:** wire `desk-arm-live.sh` into the desk boot path (desk-invariant / boot
  brief) so a fresh desk is armed without a manual run. This is a C10 activation (touches a live boot
  path) → a separate pending-activation snippet, not folded in here.
- **Organic soak telemetry:** a first-live-fire pager/summary so the first real `stage2-live` fires are
  observed, not just logged.
