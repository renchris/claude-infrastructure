# boot-resume — activation snippet (P0-10 agent half: T-P16-2 resume chain + T-P16-7 boot-delta pager)

**C10 ceiling:** the agent builds + RED-proves the post-login reboot-recovery chain
(`scripts/boot-resume.sh` + the `scripts/boot-resume-launch.sh` seam) and its `launchd` template.
The **operator** performs the live wiring below and makes the two decisions this file surfaces
(**reboot posture** and the **resume-vs-page posture switch**). Nothing here is auto-loaded; the agent
never `launchctl load`s. Until the plist is loaded, `boot-resume.sh` is a plain CLI you can run by hand.

This closes reboot-recovery gap **G-P16-1/-4**: after a reboot nothing relaunches Claude Code and the
lead supervisor's `/tmp` telemetry is wiped, so previously-open desk sessions sit dead until a human
acts. This chain runs at the next GUI login and either resumes them or pages you once — **zero human
action, or one page if deferred** (the DoD acceptance).

> **Relationship to the operator's reboot posture (plan decision #1).** *Whether* the machine reboots
> unattended and *whether* it FileVault-locks are the operator's call (auto-login+FileVault-off vs
> LaunchDaemons vs manual-morning-resume; + killing the self-reboot trigger
> `AutomaticallyInstallMacOSUpdates=false`, T-P16-1). This chain is **posture-agnostic**: whatever you
> choose, it recovers the sessions *after login*. It does **not** touch pmset/FileVault/auto-login.

## What was built (repo files, on `feat/desk-boot-resume`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `scripts/boot-resume.sh` | the chain: detect (registry×boottime) → decide (posture + per-boot idempotency) → act (page always; resume when posture=resume) → IDL | **auto-deploys** via `install.sh` (symlinks `scripts/*.sh` → `~/.claude/scripts/`); then load the plist |
| `scripts/boot-resume-launch.sh` | the TTY-coupled resume seam (opens an iTerm2 window, runs `reso-resume-one`); `--dry-run` prints the command it would run | auto-deploys with the above; resolves beside `boot-resume.sh` |
| `launchd/com.claude.boot-resume.plist` | TEMPLATE plist (`RunAtLoad` **true**, `StartInterval` 300 self-heal retry) | **operator** `launchctl bootstrap` |
| `tests/boot-resume.bats` (8) + `tests/boot-resume-launch.bats` (5) | RED-proofs (detect / dedup / page / resume-map / fail-loud / quoting) | none (CI/regression only) |

## Interface contract

```
boot-resume.sh            one pass: page or resume the sessions open at last boot, once per boot
    exit 0 = normal (fired | abstained[already-processed|no-open-sessions|no-boottime])
    exit 3 = posture=resume but the resume launcher is unresolvable (LOUD, boot NOT marked → retries)
    exit 4 = a delta exists but no desk role to page (LOUD, boot NOT marked → the 300s tick retries)
boot-resume-launch.sh <alias> <cwd> <sid> [branch]   resume ONE session in a fresh iTerm2 window
boot-resume-launch.sh --dry-run …                    print the reso-resume-one + osascript, run nothing
```

Env knobs (all default sanely; the plist sets none — pure defaults are correct):
`CC_BOOT_RESUME_MODE` (`page`|`resume`; else `<state>/mode`; else **page**) ·
`CC_BOOT_RESUME_STATE_DIR` (default `~/.claude/autonomy/boot-resume`) · `CC_REGISTRY_DIR` ·
`CC_ROLES_DIR` · `CC_IDL` · `CC_KEEPALIVE_INTERVAL` (240) · `CC_BOOTTIME_OVERRIDE` (smoke only).

## Dependencies (must hold before loading)

1. **Desk role set** — `~/.claude/cc-roles/desk` holds the pane UUID to page. Absent ⇒ the run
   fails LOUD (exit 4) without marking the boot, and the 300s tick retries until it's set. (This is
   the same channel the desk `autonomy-sweep`/`lead-supervisor` page through.)
2. **resume mode only** — `~/.reso/bin/reso-resume-one` + `~/.reso/bin/reso-keepalive` present (they
   are; shipped by the resume-sessions skill). `page` mode needs neither.
3. **`cc-notify` on PATH** — the plist prepends `~/.claude/bin`; `install.sh` symlinks it there.

## Step 1 — deploy the scripts, confirm green

```sh
# land feat/desk-boot-resume via the project-local /ship first, then either run install.sh
# (symlinks scripts/*.sh into ~/.claude/scripts) or symlink the two directly:
ln -sfn ~/Development/claude-infrastructure/scripts/boot-resume.sh        ~/.claude/scripts/boot-resume.sh
ln -sfn ~/Development/claude-infrastructure/scripts/boot-resume-launch.sh ~/.claude/scripts/boot-resume-launch.sh
bats ~/Development/claude-infrastructure/tests/boot-resume.bats ~/Development/claude-infrastructure/tests/boot-resume-launch.bats | tail -1
```

## Step 2 — SIMULATED reboot (no actual reboot, nothing real touched)

Point boottime into the future so every currently-open session looks like a ghost, page a scratch
desk target, and keep all state in a scratch dir. This exercises detect + page against the REAL
registry — the DoD "simulated login-after-reboot pages once" acceptance:

```sh
T=$(mktemp -d); mkdir -p "$T/roles"; echo "$(cat ~/.claude/cc-roles/desk)" > "$T/roles/desk"
CC_BOOTTIME_OVERRIDE=$(( $(date +%s) + 60 )) CC_BOOT_RESUME_MODE=page \
  CC_ROLES_DIR="$T/roles" CC_IDL="$T/idl.jsonl" CC_BOOT_RESUME_STATE_DIR="$T/state" \
  ~/.claude/scripts/boot-resume.sh
jq -c . "$T/idl.jsonl"            # → disposition:"fired", n_open:<N>, delivered:true
# (a real desk page lands too — that is the pager working. Re-run → abstained:already-processed.)
rm -rf "$T"
```

## Step 3 — choose the posture, then load the launchd job

**Posture switch (ruling #1: default is PAGE-only — the chain never auto-recovers unless you opt in):**

```sh
mkdir -p ~/.claude/autonomy/boot-resume
# DEFAULT (do nothing): page-only. A reboot with open sessions → exactly one desk page; you resume
#   with /resume-sessions when you choose.
# OPT IN to auto-resume (zero-touch): the chain opens a fresh iTerm2 window per open session and runs
#   reso-resume-one, then starts keepalive:
echo resume > ~/.claude/autonomy/boot-resume/mode      # flip back: echo page > …/mode  (or rm it)
```

```sh
cp ~/Development/claude-infrastructure/launchd/com.claude.boot-resume.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.claude.boot-resume.plist
launchctl print gui/$(id -u)/com.claude.boot-resume | grep -E 'state|program'   # confirm loaded
```

`RunAtLoad` is true, so it runs once immediately at load (and at every login thereafter). On this
first load the machine has **not** rebooted since the sessions started, so it abstains
(`no-open-sessions`) — correct. The real recovery happens on the **next login after a reboot**.

## Verify (after loading)

```sh
tail -5 ~/.claude/autonomy/idl.jsonl | jq -c 'select(.tool=="boot-resume")'   # run records
tail -20 /tmp/claude-boot-resume.stderr.log                                   # any exit-3/4 LOUD fail
launchctl print gui/$(id -u)/com.claude.boot-resume >/dev/null && echo loaded
```

## Rollback / kill-switch

```sh
launchctl bootout gui/$(id -u)/com.claude.boot-resume     # stop the chain immediately
rm -f ~/Library/LaunchAgents/com.claude.boot-resume.plist # (optional) remove the job
echo page > ~/.claude/autonomy/boot-resume/mode           # or just drop back to page-only (no resume)
```

Booting out the job is the single kill-switch; with it gone the chain only ever runs when you invoke
`boot-resume.sh` by hand. The posture file is the softer switch — `page` mode can never open a pane.
