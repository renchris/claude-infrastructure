# Hostile verdict: packaging claude-infrastructure as a public plugin

**Verdict: FAIL as proposed.** The portable surface is ~17 prompt-only skills; every hook and most tools are one coupled, operator-calibrated system that a plugin cannot carry, and the repo already leaks what a plugin would be blamed for.

## Ranked failure modes

1. **Privacy leak is already live, and a plugin amplifies its audience.** `accounts.json` is tracked, public since 2026-07-10, holds 7 personal emails and says `"Emails are fine: this repo is private"` (accounts.json:3). `hooks/enforce-email-formatting.py` hardcodes two personal mailboxes and `<redacted-email>` (26 `reso.gl` hits across hooks); the directory review flow sends every installer to "View on GitHub" (code.claude.com/docs/en/plugins/security § Review), i.e. straight at this file.

2. **Hooks are a system, not units.** 49/96 hooks parse transcripts, 47 call `cc-*` bin tools, 16 source `hooks/lib` (38 files); `settings.example.json:447` says the Stop chain "order matters… MUST be reproduced". Plugin `hooks.json` merges into the user's chain with no ordering control, `${CLAUDE_PLUGIN_ROOT}` changes per version (components doc § path variables), and plugin `settings.json` keeps only `agent`/`subagentStatusLine`, so env kill-switches (`CC_UNATTENDED_ASK_GUARD_DISABLED`, hooks/cc-unattended-ask-guard.sh:26) and permissions do not ship.

3. **Behaviour a stranger did not consent to.** `session-continue.sh` and `completion-assert.sh` exit 2 on Stop (forced continuation; kill-switch keyed to English phrases like "and stop"); `cc-unattended-ask-guard.sh` denies `AskUserQuestion`; `enforce-email-formatting.py` R1 denies all Graph sends "ABSOLUTE… no override". All run outside the sandbox with full user privileges (security doc).

4. **Calibrated to one operator's scar tissue.** 587 incident-dated lines in hooks; predicates derive from FM1/2026-08-24 incidents. 19/38 skills reference Fable/next2-4/`cc-*`/`~/Development`; 61/122 bin tools depend on `~/.claude/{hooks,scripts,bin}`. Nothing generalises without rewriting the thresholds it exists to encode.

5. **Legal.** No LICENSE: default all-rights-reserved, so the directory would list unlicensed code. `skills/kpmg-deck` ships KPMG brand tokens (`assets/kpmg_deck/brands/kpmg.json`) under a third party's trademark. `vendor/codex-security` is Apache-2.0 and needs NOTICE carriage.

6. **Fork drift is guaranteed by the repo's own doctrine.** 422 commits touched hooks/skills/bin in 30 days (190 in hooks). `LOCAL_ONLY.md` already rules a tracked copy of upstream text "a fork that silently diverges"; a plugin is that copy, and on the operator's Mac plugin `bin/` joins PATH beside `~/bin` (122 `cc-*` names collide).

## The dimension most likely missed

**The update channel, not the snapshot.** Marketplace auto-update rewrites plugin files on disk in the background (security doc § Updates); this repo lands to trunk without PRs (`/ship`, `/pr`: "usually not: push to trunk") at ~6 hook commits/day. Every landed commit becomes unreviewed remote code executing with full privileges on every installer's machine, and the directory safety scan is stated only at submission. A packaging analysis audits the files it would ship today; the failure is what ships tomorrow.
