---
status: in-progress
---

# PERMISSION_PROMPT_CONSOLIDATION — stop autonomous sessions stalling on prompts that approve safe, repeatable actions

**Scope (frozen, 2026-09-24):** operator directive, verbatim: *"Can we also /handoff Opus 5.5 high consolidating
permission requests and pretool hook requests to scalable patterns to our allowlist?"* So: census every
permission prompt and PreToolUse-hook `ask` that interrupted a session, cluster them into scalable patterns, and
remove the safe ones at the right layer — hook false positives FIXED IN THE HOOK (landed, bats red on parent);
settings allow/ask-rule changes STAGED as one operator-applied step (never written by an agent). Dangerous asks stay.

## Phase 0 — Agent Team Orchestration

**Execution locus:** S — one dispatched session (this plan's owner), Opus 5.5 @ high. It may fan out read-only
research subagents for the census; hook edits stay on the session itself (one owner per hook file).
**Lead context budget + succession point:** hold ≥50% for judgment; `--recycle` after the census is persisted here.

## Evidence that triggered it (2026-09-23/24, RESO_LATENCY_100P)

Three dispatched reso sessions sat ~45 min to 8 h at prompts nobody was watching:
1. `hooks/validate-bash.sh` family: `rm -r on non-build-artifact target: 'src/app/api/w0-probe'` and `'$O/tmp'` —
   scratch paths the session itself had just created (a probe route; a tmp dir under a variable).
2. `Ask rule Bash(git stash drop:*) overrides auto mode` — present in ALL FIVE config dirs' settings.json
   (`permissions.ask`, beside `git stash clear:*`) — on a session dropping its OWN temporary stash
   (`git stash push -m X … && git stash apply <X> && git stash drop <X>`, a red-on-parent capture idiom).
3. `Contains command_substitution` — not statically analysable, so auto mode deferred to the prompt.

## Method

1. Census, read-only: `bin/cc-permission-harvest` and `bin/cc-permission-audit` (read their own caveats — the
   audit's `approved 0 · unknown N` is an unpopulated join key, not a measurement) plus the transcripts' hook-ask
   records. Output: a ranked table — pattern · count · sessions stalled · stall minutes · layer (hook ask /
   settings ask rule / auto-mode classifier / no allow rule) · safe-to-remove? · the scalable rule or hook change.
2. Hook layer (yours to land): fix false positives scoped to the EFFECT, never by widening a denylist spelling
   (memory: denylist-enumerates-spellings-not-the-class). Every change gets a bats case red on the parent and a
   case proving the dangerous sibling (`rm -rf src`, `rm -rf /etc`, `$HOME`) still asks.
3. Settings layer (the operator's to apply): ONE staged step — a `migrations/` c10 entry or a `cc-do` item — that
   edits the allow/ask lists in every config dir identically (accounts are interchangeable; a fork is a defect).
   Name each rule's census count and why it is safe. Never write settings*.json yourself.
4. The classifier layer (command substitution etc.): prefer reshaping the IDIOM the agents use (a helper script
   agents call instead of the inline chain) over any allow rule, and record which prompts are structural.

## Status

| Step | State | Evidence |
|---|---|---|
| Plan + fire | fired 2026-09-24 | — |
| 1. Census | done 2026-09-24 | ranked table below |
| 2. Hook layer | landed (shas in § Landed) | 3 fixes, bats red on parent + dangerous siblings |
| 3. Settings layer | STAGED — `migrations/0038-git-ask-rules-to-hook.sh` (c10) | operator runs it once |
| 4. Classifier layer | recorded, not changed | structural row below |

### Census — ranked by stalled hours (30 days to 2026-09-24)

Sources: `~/.claude/autonomy/permission-archive` (the prompt oracle, 2,669 Bash prompts / 393 sessions),
`~/.claude/logs/validate-bash-decisions.jsonl`, `~/.reso/curl-audit.jsonl`, the 2026-09-20 weekly
`cc-permission-harvest` proposal. "Stall h" is the archive's `waited_s` joined by session ±15 s; it
counts time a prompt sat open, including sessions nobody was watching. `cc-permission-audit`'s
`approved 0 · unknown N` was NOT used: its join key is unpopulated (its own caveat). **Fixed** counts are
a REPLAY of the same recorded commands through the parent (a7a372d2c) and the new hook, so they are
measured flips, not estimates.

| # | Pattern | Prompts | Sessions | Stall h | Layer | Safe to remove? | Change |
|---|---|---|---|---|---|---|---|
| 1 | structural: redirect-to-file 538 · `$( )` 405 · heredoc 364 · `cd`+`git` 347 · multi-`cd` 195 (kinds overlap) | 1,182 | — | ~777 | auto-mode classifier (not statically analysable) | no rule can clear it | none this plan — the lever is the idiom / `smart-bash-allowlist.py` (§ Classifier layer) |
| 2 | curl-gate: URL in a loop/assignment variable (`for u in "https://…"; do curl "$u"`) | 596 | 38 | ~52 | hook ask (`curl-gate.py`) | **yes** — the URL is literal in the command | **fixed**: resolve decidable same-command bindings, judge every value with the unchanged `decide()` |
| 3 | curl-gate: credential-bearing GET to loopback (`curl -b jar http://gn.localhost:3000/…`) | 126 | 15 | ~50 | hook ask | **yes** — exfiltration needs a remote receiver; curl pins `*.localhost` to loopback (measured) | **fixed**, only without `-L`/`--location-trusted` |
| — | curl-gate rows 2+3+info-only, measured by replay | **662 → allow** | 40 | **~73** | | | 0 flipped to a new ask/deny |
| 4 | settings ask `Bash(git push:*)` | 371 | 165 | ~148 | settings ask rule | **no** — landing goes through `/ship` | none (deliberate) |
| 5 | settings ask `Bash(git reset --hard:*)` + hook warn | 64 | 40 | ~67 | settings ask + hook ask | **yes when lossless** (clean tree, no local commit missing from the target) | **hook owns it**; rule removal STAGED (0038) |
| 6 | settings ask `Bash(git stash drop:*)` | 29 | 13 | ~57 | settings ask | **yes for a drop of the entry the command re-found by its own tag** (the harness's own stash recipe) | **hook owns it**; rule removal STAGED (0038) |
| 7 | validate-bash rm -r: relative target after a `cd` in the command | 178 | 55 | ~46 | hook ask | no — the hook cannot know the cwd after a `cd` | none; agents should use an absolute scratchpad path |
| 8 | validate-bash rm -r: literal `/tmp/…` path, directly or via `$VAR` | 203 | ~60 | ~32 | hook ask | no — `/tmp` holds live infra (daemon sockets, land locks); decided 2026-09-10, re-confirmed | none; use the scratchpad or `T=$(mktemp -d)` (both already permitted) |
| 9 | validate-bash rm -r: target inside a heredoc body WRITTEN to a file (`cat > x.sh <<'EOS' … rm -rf "$T" … EOS`) | **68 → pass** (replay) | 31 | **~25** | hook ask | **yes** — this command never executes it | **fixed**: a heredoc body is scanned only when a shell consumes it |
| 10 | validate-bash rm -r: junk "targets" `EOF` `echo` `}` `done` (newline) | 65 | 24 | ~23 | hook ask | yes | already fixed 2026-09-23 (efc0ef253) |
| 11 | validate-bash rm -r: relative repo path (`src/app/api/w0-probe`) | 25 | 15 | ~28 | hook ask | no — an untracked dir in a repo can be uncommitted work | none |
| 12 | settings ask `Bash(git restore:*)` | 11 | 10 | ~25 | settings ask | **yes for `--staged` without `--worktree`** (unstage only) | **hook owns it**; rule removal STAGED (0038) |
| 13 | curl-gate: POST/PUT to an unknown host · credential to a third-party host | 196 | 28 | ~13 | hook ask | no — a write or an exfiltration shape | none (the gate doing its job) |
| 14 | validate-bash `git clean -x/-X` | 6 | 1 | <1 | hook ask | no — paid assets | none |

The plan's three triggering cases: (1) `rm -r 'src/app/api/w0-probe'` is row 11 and `'$O/tmp'` row 8 —
both deliberately still ask; (2) the stash-drop idiom is row 6 — fixed once 0038 runs; (3) "Contains
command_substitution" is row 1 — structural.

**Found while fixing, fixed in the same change (deny direction):** `curl-gate.py`'s entry filter split
statements on `[;&|]` only and required them to START with `curl`, so `echo x⏎curl http://169.254.169.254/`,
`for …; do curl …`, `(curl …)` and `if …; then curl …` were never gated at all — no IMDS, RFC1918 or
pipe-to-shell deny. It now splits on newline / `$(` / `(` too and skips leading keywords and prefixes.
Likewise `git -C x reset --hard` and `git reset -q --hard` matched neither the old hook regex nor the
settings rule; the git-ownership block now asks on them.

### Landed

(filled at land)

### Settings layer — the ONE operator step

`migrations/0038-git-ask-rules-to-hook.sh` (class `c10`, staged by the converger, never run by an agent)
removes exactly `Bash(git reset --hard:*)`, `Bash(git stash drop:*)`, `Bash(git restore:*)` from
`~/.claude/settings.json` (every account links to it since 0037). It refuses unless the LIVE
`validate-bash.sh` carries the GIT-OWNERSHIP block, backs up first, and verifies by content that nothing
else changed. `git push`, `git stash clear`, `fly deploy` stay. No allow rule is proposed: the weekly
harvest (2026-09-20) found `proposed=0` after its eleven gates, which the permission-harvest skill
records as the expected steady state.

### Classifier layer — recorded, not changed

Row 1 is 44% of all Bash prompts and ~65% of the stalled hours, and no allow rule of any form reaches it.
Its lever is the idiom agents write (redirects to files, `$( )`, heredocs, `cd && git`) and
`hooks/lib/smart-bash-allowlist.py`, which already decomposes `$( )`. That is the standing
`permission-harvest-structural-levers` row's work, not this plan's.
