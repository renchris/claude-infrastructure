# FM2 fire-path stack — activation lines

Program C (FM2 idle-standoff fire path). All code is committed on `feat/desk-fm2-stack`; this file
records the **activation lines only** (C10 ceiling: this beat did NO live wiring — no settings.json,
no launchd, no `~/.claude/bin` symlink writes). The wiring beat / lead applies these.

Commits: `412722a` (P0-11+P0-12) · `30c8352` (P0-15) · `c372917` (P0-16) ·
`ea8c07e` (disposition hardening) · `27c8341` (bin/desk-assert).

---

## 1. `bin/desk-assert` → PATH (REQUIRED)

`desk-assert` is a new bin and is NOT yet symlinked into `~/.claude/bin`. Add it to the
`wiring-all.sh` symlink loop (SECTION 2, the `for t in …` list at line ~60), so it lands the same
way as `cc-sessions`/`cc-notify`:

```diff
-for t in cc-wait cc-deathwatch-kqueue cc-run cc-announce cc-respawn cc-route cc-teardown cc-teardown-safety-gate.sh \
-         cc-bind cc-board cc-context cc-sessions cc-notify cc-await-ping; do
+for t in cc-wait cc-deathwatch-kqueue cc-run cc-announce cc-respawn cc-route cc-teardown cc-teardown-safety-gate.sh \
+         cc-bind cc-board cc-context cc-sessions cc-notify cc-await-ping desk-assert; do
```

Or, as a one-off until wiring-all runs: `ln -sf "$REPO/bin/desk-assert" "$HOME/.claude/bin/desk-assert"`.

Verify: `desk-assert <a-live-sid> --witnessed-ref <fixed-ref>` prints `GROUNDED …` / `UNGROUNDED: …`.

## 2. P0-15 role indirection (INTEGRATES with the EXISTING cc-roles map)

`wiring-all.sh` already creates `~/.claude/cc-roles/{desk,orchestrator,operator}` (SECTION 2). This
beat only WRITES/REFRESHES those files:

- `handoff-fire.sh --as-role <role>` writes the FIRED pane at every fire (post-engagement).
- recycle keeps `cc-roles/*` current for its own pane; `self-close --successor` repoints any role
  naming the closing pane → the verified-alive successor.

**No wiring needed for the writer.** For the SO-1 loop to fully close, the READER
`cc-await-ping --role <role>` (follow the role file each poll) must exist — that is a **comms-beat**
dependency, NOT in this stack. Until then, role files stay current but pings still address by uuid.
Desk fires that want role indirection must pass `--as-role` (e.g. `--as-role operator`).

## 3. P0-11/P0-12/P0-16 handoff-fire changes (INTRINSIC — no wiring)

`handoff-fire.sh` is already invoked by `/handoff` + `hooks/waiting-recycle.sh`. The new behavior is
intrinsic to the script:

- **P0-11 engagement verify**: every non-recycle, non-dry fire now polls for transcript/registry
  birth and FAILS LOUD (`FIRE FAILED — never engaged`, exit≠0) instead of a false `→ fired`.
  Tunable env (defaults in parens): `FIRE_ENGAGE_TIMEOUT` (120s), `FIRE_ENGAGE_RETRY` (60s),
  `FIRE_ENGAGE_INTERVAL` (3s). Test-only seams: `FIRE_ENGAGE_MARKER`, `IT2_BIN`.
- **P0-12 registration guarantee**: writes a provisional `cc-registry` row if the P8 SessionStart
  row doesn't appear ≤`FIRE_REG_TIMEOUT` (30s); P8 `register()` overwrites it.
- **P0-16 /goal guard**: a `/goal` line body >`GOAL_MAX_CHARS` (4000) hard-fails pre-fire.

No consumer changes required. NOTE: the engagement poll adds up to ~120s (+60s re-poll) of wall
time to a non-recycle fire on a MISS; on a hit it returns as soon as the transcript/registry
appears (typically seconds).

## 4. handoff-disposition hardening (INTRINSIC — opt-in flags)

`handoff-disposition.sh` is run by the desk model each post-fire turn (per `commands/handoff.md`).
The hardening is intrinsic:

- fail-CLOSED `R-REGISTRY-INDETERMINATE` when `cc-sessions` errors (rc≠0); word-boundary slug match.
- `--deliverable <path>` (repeatable) and `--payload <file>` (extracts `DELIVERABLE: <path>` lines)
  add a completeness axis (`deliverables_missing`). **Opt-in by the caller** — the desk/disposition
  contract should pass the fired brief's declared deliverables to exercise it.

Optional doc follow-up (owned elsewhere): mention `registry_indeterminate` / `deliverables_missing`
+ the two new reasons in `commands/handoff.md`'s disposition contract section.

## 5. Verification (run in the worktree before/after wiring)

```bash
for t in fire-autonomy fire-engagement handoff-splitright handoff-disposition notify-back desk-assert; do
  bats "tests/$t.bats"
done
# 81 passing: fire-autonomy 23 · fire-engagement 9 · handoff-splitright 9 · handoff-disposition 24 · notify-back 9 · desk-assert 7
```
