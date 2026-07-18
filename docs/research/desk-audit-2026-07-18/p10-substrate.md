# P10 — Runtime Substrate & 24/7 Plumbing (what actually runs unattended)

Beat owner: orchestrator-desk investigation. READ-ONLY live system checks + repo code.
Goals mapped: **a** = 24/7 unattended runtime · **b** = FM1 (premature-done/purpose-loss) guard · **c** = FM2 (idle-standoff) recovery.
Coverage: read the actual code of 14 in-scope files + live-inspected 11 launchd plists, 5 config dirs, and 8 log/state files. Empirical = read/ran; Theoretical = inferred.

## 1. Inventory (one row per in-scope asset)

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Serves | Gap |
|---|---|---|---|---|---|---|
| com.chrisren.cc-reaper | FM2 idle-session reaper (the standing sweep) | launchd **StartInterval 300s**, RunAtLoad 0, loaded, exit 0 | bin/cc-reaper, cc-classify, cc-teardown, PATH fix (36f9d64) | out.log live (Jul18 03:34, "33 classified·0 reaped") GREEN | a,c | G-1,G-5 |
| com.claude.lead-supervisor | Out-of-session watchdog for multi-day unwatched runs — PAGES, never auto-recovers | launchd **KeepAlive 1**, RunAtLoad 1, **running PID 17867 (3d7h)** | scripts/lead-supervisor.sh, idl.jsonl, pages/ | supervisor.log live (sweep ~35s, swept=116/findings=93) GREEN | a,b,c | G-1,G-2 |
| com.claude.team-orphan-reaper | Reaps orphaned Agent-Team worktrees/panes | launchd **StartInterval 600s**, loaded, exit 0 | scripts/team-orphan-reaper.sh | launchctl status 0 | a,c | G-1 |
| com.chrisren.restic-claude-archive | Weekly off-machine backup of CC binary archives → B2 | launchd **StartCalendarInterval Sat 02:00** (Weekday 6) | restic, 4 Keychain creds, ~/.claude/archives/claude-code/ | restic-backup.log "9 snapshots, forget+prune OK" (ran today) GREEN | a | G-1,G-10 |
| com.chrisren.watch-getAppState-fix | GH-poll for a regression FIXED in 2.1.114 | launchd **Cal 09:07 daily**, loaded, **exit 1** | gh, scripts/watch-getAppState-fix.sh | header: "OBSOLETE… safe to delete after 2026-05-02" | (none) | G-9 |
| com.chrisren.watch-claude-code-2118-hold | GH-poll: when safe to leave the 2.1.114 hold (#52251/#52522) | launchd **Cal 09:12 daily**, loaded, **exit 1** | gh (PATH has /opt/homebrew), scripts/watch-…-2118-hold.sh | header confirms live hold rationale | a | G-9(minor) |
| com.chrisren.verify-2114-archive | Verifies pinned-114 archive integrity | launchd **Cal 09:00 daily**, RunAtLoad 1, exit 0 | ~/.claude/archives | launchctl status 0 | a | — |
| com.chrisren.screenshot-clipboard | ⌘⇧4 file→clipboard watcher (operator UX) | launchd **WatchPaths ~/Screenshots**, exit 0 | scripts | launchctl status 0 | (ux) | — |
| com.claude.session-search-{sweep,backfill} | Session-transcript index maintenance | launchd (schedule not surfaced by plutil) | index scripts | loaded, exit 0 | (b, indirect) | uncertainty |
| hooks/validate-bash.sh | PreToolUse Bash deny/ask (DDL, --no-verify, rm-rf, force) | **hook-enforced** PreToolUse(Bash), timeout 10s, wired in all 5 dirs | lib/is-true-flag.sh, jq | code read; wired (jq) GREEN | a | G-8 |
| hooks/rm-safe-allowlist.sh | PreToolUse affirmative-allow of regenerable rm (stops rm ask) | **hook-enforced** PreToolUse(Bash), timeout 5s, wired in all 5 dirs | jq | code read — clean case-based guards GREEN | a,c | — |
| hooks/smart-bash-allowlist.sh | 5-class bash auto-allow (git commit/rm/sed/push/chmod) | **DEAD — wired in 0 of 5 dirs** | jq, grep | grep bug lines 111/135 (inert) | (none) | G-7 |
| hooks/pre-session-validate.sh | SessionStart: auto-rollback broken CC version + strip fable-poison model | **hook-enforced** SessionStart, fail-open | ~/.claude-versions/{current,MANIFEST.jsonl} | code read; current→2.1.114 GREEN | a | G-3 |
| hooks/config-mirror-assert.sh | SessionStart: re-assert knowledge-layer mirror for non-default accounts | **hook-enforced** SessionStart, `\|\| true` fail-open, fixes NEXT session | lib/config-mirror.zsh | code read | a | uncertainty |
| hooks/backup-before-write.sh | PreToolUse Write/MultiEdit auto-backup + overwrite guard | **hook-enforced** PreToolUse(Write\|Edit) | jq, ~/.claude/backups | 233 .bak, auto-prune keep-10 GREEN | b (recovery) | G-8 |
| hooks/cache-expiry-{tracker,warning}.sh | Stop writes .last-interaction; UserPromptSubmit warns on >5m idle | **hook-enforced** (advisory only, never blocks) | .last-interaction | code read — advisory | (cost) | — |
| hooks/push-critical.sh | Pushover phone break-through on "needs input" | **hook-enforced** Notification — **INERT (no PUSHOVER_TOKEN)** | PUSHOVER_TOKEN/USER env, curl | code read; env unset | b,c (backstop) | G-6 |
| scripts/restore-file.sh | Manual recovery from backup-before-write .bak | **manual** (+ ~/bin/restore-file symlink) | ~/.claude/backups | code read — atomic temp+mv GREEN | b (recovery) | — |
| scripts/smoke-test.sh | Pre-promote 5-test firewall; flips `current` only on --promote+pass | **manual-only** | version dirs | code read — the anti-auto-upgrade firewall | a | — |
| scripts/watch-getAppState-fix.sh / watch-…-2118-hold.sh | GH pollers (see launchd rows) | launchd | gh | read | a | G-9 |
| install.sh | Idempotent symlink/copy deployer of repo → ~/.claude | **manual** (`ln -sf`, replace-symlink-with-copy logic) | repo | code read; idempotent GREEN | a | — |
| bin/claude-latest + claude-update + record-version.sh | Version launcher + MANIFEST writer (skip=hold, candidate=auto-install) | manual/launcher | MANIFEST.jsonl | MANIFEST read — 114 pinned, all >114 skip | a | — |

## 2. Mechanism + the 3am strand list

**Config topology (empirical, live):** 5 INDEPENDENT settings.json (distinct inodes 233158084/233158086/234311689) — `~/.claude`(bare)·`.claude-next`·`.claude-secondary`·`.claude-tertiary`·`.claude-quaternary`. **hooks/ IS symlinked** (`~/.claude-next/hooks → ~/.claude/hooks`) so one hook file serves all accounts; **settings.json is NOT** (copies → drift). `~/.claude` is a real dir; live hook/bin/script files are **symlinks into the repo** (`~/.claude/hooks/validate-bash.sh → …/claude-infrastructure/hooks/validate-bash.sh`) → **a repo edit is instantly live across all accounts, no staging**. statusline.sh + settings.json are copies (repo edit NOT live).

**Permission model (empirical):** all 5 dirs `defaultMode:auto`; auto-mode permits anything not matching an **ask-rule**. Ask-rules (identical in all 5): `git push:* · git restore:* · git stash drop:* · git stash clear:* · fly deploy:* · git reset --hard:*`. Precedence deny>ask>allow (ask shadows allow). validate-bash.sh + rm-safe-allowlist.sh are the only wired Bash PreToolUse hooks; **smart-bash-allowlist.sh is wired nowhere**. Agents CANNOT self-edit settings.json (classifier blocks Write/Edit) → permission changes are operator-script-only (a KEEP guardrail).

**3am strand list — operations that stop & wait for a human at night:**
- **S1 (structural, worst):** an unattended **reboot** kills every desk job — all are per-user **LaunchAgents** (`/Library/LaunchDaemons` has **zero** claude jobs); Agents load only in a GUI login session. With FileVault (forces pre-boot auth) there is no auto-login → cc-reaper, lead-supervisor, restic all dead until console login. Evidence: `ls /Library/LaunchDaemons | grep claude` empty; all 11 jobs in `~/Library/LaunchAgents`.
- **S2 (agent-invoked):** `git push` / `git restore` / `git reset --hard` / `fly deploy` through the Bash tool → **ask-prompt** (by design — the human landing gate). Autonomous `/ship` strands IF it runs `git push` directly; safe only if wrapped in a script whose Bash-tool command string isn't `git push …` (unverified — cross-beat).
- **S3 (agent-invoked, theoretical):** un-allow-listed **desk CLIs** run through the Bash tool (`cc-teardown`, `claude-accounts`, `cc-respawn`, `cc-route`, `cc-classify`, `cc-wait`, `cc-announce`, `cc-bind`, `claude-kimi`) may trip the auto-mode **classifier** ("unknown custom CLI") → prompt. `cc-notify`/`handoff-fire.sh` ARE allow-listed; these are not.
- **S4 (backstop dead):** when a session genuinely needs input, the **Pushover** phone break-through (push-critical.sh) is **INERT** (PUSHOVER_TOKEN unset) → no human is paged; the standoff sits silent.
- NOT strands: cache-expiry (advisory), the 9am watch/verify jobs (non-blocking, notify-only), a hung PreToolUse hook (bounded by 5s/10s timeout).

**Version integrity (empirical):** `~/.claude-versions/current → 2.1.114` (deliberate pin); installed 2.1.80/111/112/113/114/183; **all >114 are MANIFEST `skip`** (skip=hold silences the claude-latest nag; `candidate` would AUTO-INSTALL — the documented trap). pre-session-validate.sh rolls `current` back to the highest non-skip working binary if 114 breaks; also strips a `fable`-poison saved model (a `/model fable` save into shared settings would brick the stable track). Drift is prevented by design.

## 3. Gaps & fragilities

| ID | file:line / evidence | FM | Sev | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P10-1 | `/Library/LaunchDaemons`=∅; all jobs in `~/Library/LaunchAgents` | 24x7 | **P0*** | Unattended reboot (forced macOS update / power blip) + FileVault → cc-reaper + lead-supervisor + restic dead until a human logs in at console; running panes also killed | Convert the 4 continuous jobs to LaunchDaemons, OR enable auto-login (security call), OR a documented post-reboot resume runbook (pairs with resume-sessions skill). *P0 severity is catastrophic-but-conditional on a reboot. |
| G-P10-2 | `~/.claude/autonomy/idl.jsonl` = **114 MB**, +~38MB/day, mtime live | 24x7 | P1 | Supervisor telemetry grows unbounded on the ~35s sweep hot path → eventual sweep-slower-than-interval and disk creep; shared with reaper | size-capped roll / retention on idl.jsonl; confirm sweep tails (not full-scans) the file |
| G-P10-3 | pre-session-validate.sh:49 `SETTINGS_FILE="$HOME/.claude/settings.json"` (hardcoded) | 24x7 | P1 | Model-poison guard heals only the default account; a `/model fable` save into next2/3/4 settings.json is NOT healed → that account's plain launch bricks ("issue with selected model") | Use `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json` |
| G-P10-4 | live hooks are repo symlinks; project CLAUDE.md notes shared checkout "frequently sits on a feature branch" | 24x7 | P1 | A session checking out a feature branch in the shared checkout makes ALL live hooks machine-wide reflect that (possibly broken) branch → machine-wide session breakage | Enforce worktree-only for infra edits (hook/guard); never leave the shared checkout off main |
| G-P10-5 | settings.json allow: cc-teardown/claude-accounts/cc-respawn/cc-route/cc-classify absent (Empirical: 0 grep hits); classifier behavior Theoretical | 24x7 | P1 | Agent-initiated desk-CLI call prompts via the classifier at night → strand | Add the desk CLIs to allow across 5 dirs (operator script; agents can't self-edit) |
| G-P10-6 | push-critical.sh:21-22 exit-0 unless PUSHOVER_TOKEN/USER set; unset in env+.zshenv+.zshrc | FM1/FM2 | P1 | "needs input" never pages the operator → the human backstop for a stuck session is silent | Arm PUSHOVER_TOKEN/USER in ~/.zshenv, OR document the backstop as intentionally off |
| G-P10-7 | settings.json 5-copy independence (memory: next4 already drifted, missing a deny) | 24x7 | P1/P2 | A safety `deny`/`ask` present in 4 accounts silently missing in a 5th → that account runs looser than intended | settings-drift assertion (config-mirror-assert analog for settings.json) |
| G-P10-8 | smart-bash-allowlist.sh:111,135 `grep -E '(?!…)'` → ugrep exit 2 (verified) | 24x7 | P2 | INERT now (wired nowhere); if ever re-enabled, the sed/chmod path-traversal + abs-path guards fail-open (`../`, `/etc/…` auto-allowed) | Replace `(?!…)` with case/`[[ ]]` guards like rm-safe uses, or delete the file |
| G-P10-9 | `~/.claude/logs/bash-commands.log` 89MB + bash-execution.log 94MB; validate-bash.sh:164 appends every cmd | 24x7 | P2 | Unbounded log growth (disk 5.1TB free → not imminent); hot-path append every Bash call | logrotate / size cap in a launchd job |
| G-P10-10 | watch-getAppState-fix.sh:4-13 "OBSOLETE… safe to delete after 2026-05-02"; still loaded, exit 1 daily | none | P2 | Dead-weight job fails daily (benign); clutters launchctl + could mask a real failure | `launchctl bootout` + archive the plist |
| G-P10-11 | restic-claude-archive-backup.sh:26-29 Keychain creds fatal (exit 1) | 24x7 | P2 | Reboot before Keychain unlock at Sat 02:00 → restic backup skipped that week (retries next week) | Keychain-unlock check + notify; low freq |

## 4. Task candidates

| ID | action | acceptance criterion | depends-on |
|---|---|---|---|
| T-P10-1 | Reboot-survival for the 4 continuous jobs (LaunchDaemon conversion OR auto-login OR resume runbook) | after a simulated reboot with no manual login, cc-reaper+supervisor resume ≤10min (or runbook restores ≤5min) | operator security call (FileVault/auto-login) |
| T-P10-2 | Cap/rotate idl.jsonl + bash-commands.log + bash-execution.log | files capped <X MB; supervisor sweep stays < interval | G-2,G-9 |
| T-P10-3 | pre-session-validate model-guard → `$CLAUDE_CONFIG_DIR` | a fable-poisoned next3 settings heals on next3 SessionStart | — |
| T-P10-4 | settings.json drift assertion across 5 dirs | a deny/ask present in 4 but missing in 1 is surfaced at SessionStart | G-7 |
| T-P10-5 | Arm Pushover (or document off) | test push fires from push-critical | operator secret |
| T-P10-6 | Allow-list the un-covered desk CLIs (operator script) | agent-initiated cc-teardown/claude-accounts run with no prompt | verify S3 is real first (uncertainty U1) |
| T-P10-7 | Remove obsolete watch-getAppState-fix job | not in launchctl list; plist archived | — |
| T-P10-8 | Fix/delete smart-bash-allowlist grep lookahead | selftest: sed/chmod path-traversal guard blocks `../` | G-8 |

## 5. Cross-beat dependencies

- **Reaper beat:** cc-reaper is healthy but reaps **0** persistently ("33 classified·0 candidates"; keep-reasons dominate) — verify the safe-candidate classifier isn't over-conservative for genuinely idle-done sessions (FM2). idl.jsonl (G-2) is shared reaper/supervisor telemetry.
- **Landing-safety beat:** `git push:*` ask-rule means autonomous `/ship` either strands (direct push) or must wrap push in a script — confirm which the project-local /ship does. The desk's "autonomous landing" claim has a by-design human gate here.
- **Comms beat:** push-critical.sh + completion-push.sh (Pushover + cc-announce) are the FM1/FM2 human-alert channel — inert without PUSHOVER_TOKEN (G-6).
- **Lead-crash beat:** lead-supervisor + lead-deathwatch + lead-reconciler = crash-recovery stack; RULING #1 = **pages, never auto-recovers** (operator 2026-07-14). Structural blindness to in-session modals is declared, not papered.

## 6. Adversarial self-pass (what a hostile reviewer would say I missed — then covered)

1. *"You listed launchd jobs but didn't ask if they even run after a reboot."* → Covered: G-1 (P0) — all LaunchAgents, no Daemons, need GUI login; the single biggest 24/7 hole.
2. *"You found the cc-reaper error log and assumed it was fine."* → Covered empirically: err.log mtime Jul17 17:10 (stale, pre-36f9d64) vs out.log Jul18 03:34 (live); plist now has the PATH fix; the "command not found" is residue, reaper runs GREEN.
3. *"The grep bug — is that hook even active?"* → Checked all 5 dirs: smart-bash wired NOWHERE (dead); downgraded P2 with a re-enable-landmine caveat, not overstated as live.
4. *"Can a hook hang a session forever?"* → No: PreToolUse Bash hooks carry 5s/10s timeouts. Bounded.
5. *"Is the infra backed up off-machine, or only restic (which excludes it)?"* → Checked: restic covers only `archives/claude-code/`; the infra itself is git — and the repo IS pushed to github.com/renchris/claude-infrastructure, `origin/main..HEAD=0` (current 2h ago). Off-machine backup exists.
6. *"Supervisor is 'running' — is it looping or wedged?"* → Verified: PID 17867, 3d7h, 0.6% CPU, supervisor.log sweeps every ~35s. Alive.

## 7. Uncertainties

- **U1 (Theoretical):** whether the auto-mode classifier ACTUALLY prompts on un-allow-listed desk CLIs (S3/G-5). Inferred from memory's classifier description; not observed live. Confirm via a transcript grep for prior prompts on `cc-teardown`/`claude-accounts` before spending on T-P10-6.
- **U2:** `autoLoginUser` / FileVault state not readable without sudo → can't confirm whether auto-login already mitigates G-1. If auto-login is on AND FileVault off, G-1 downgrades to P2.
- **U3:** whether lead-supervisor full-scans vs tail-reads idl.jsonl per sweep (impact sizing of G-2). JSONL implies tailing; unverified.
- **U4:** session-search-{sweep,backfill} schedules not surfaced by plutil grep (empty) — likely WatchPaths/StartInterval I didn't decode; low desk-criticality (index maintenance).
- **U5:** watch-2118 exit-1 exact line (pipefail-on-transient-gh vs final-test-false) not traced; benign either way (9am, notify-only).
- **U6:** PUSHOVER_TOKEN could live in ~/.zprofile/.zlogin or launchd-injected env (checked env + .zshenv + .zshrc only).
