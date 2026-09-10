# Permission-prompt census, 30 days to 2026-09-10

Instrument: replay of all 2,838 archived Bash permission prompts
(~/.claude/autonomy/permission-archive) through TODAY's hook chain, so counts are
what would prompt NOW, not what prompted then. Two independent runs (sequential and
10-way threaded) returned identical tallies.

| bucket | n | reachable from settings.json? |
|---|---|---|
| hook-emitted ask/deny | 1,038 | NO — proven below |
| decided by static permission rules | 1,655 | partially |
| allowed by smart-bash-allowlist | 145 | n/a |

## Hook asks by reason (1,038)
721 rm -r on non-build-artifact target   (69%)
136 curl: No URL parsed
 87 git reset --hard
 60 curl: read to unvetted host + credential
 24 curl: POST unknown host
 10 other

## The 721 rm asks, by what the target actually is
165 X=$(mktemp -d)          -> FIXED (834bd7b5d), 136 measured clear
152 literal path under /tmp or /private/tmp   -> NOT widened; see below
194 relative target, cwd = repo/worktree      -> correctly prompts (`rm -rf src`)
 90 relative target, cwd = temp/scratchpad
 69 var-from-var chains
 51 other

## The 60 credential-carrying curl asks
27 are LOOPBACK dev servers (gn.localhost, studio60.localhost, church.localhost,
   key.localhost, clubvinyl.localhost, localhost). is_localhost_dev() accepts only
   exact "localhost"/"127.0.0.1" AND a fixed port list, so every *.localhost tenant
   and every port outside that list falls through to the credential arm. A cookie to
   loopback cannot leave the box, so this is the same safety case already allowed.

## The 136 "No URL parsed"
85 have the URL in a shell variable (`for u in <literal urls>; do curl "$u"`). Same
decidable shape validate-bash already resolves for rm targets.

## PRECEDENCE — measured on the live binary (2.1.260), not inferred
Three arms, one variable, positive control green:
  C: allow rule only, no probe hook      -> tool RAN
  A: hook returns ask, no allow rule     -> BLOCKED (probe-ask-from-hook)
  B: hook returns ask + allow rule       -> BLOCKED (probe-ask-from-hook)
=> A permissions.allow rule does NOT suppress a PreToolUse hook's ask.
Therefore the 1,038 hook prompts are UNREACHABLE from settings.json, and adding
Bash(curl:*) is SAFE: curl-gate's own ask/deny survive it.

Corpus check attempted first and WITHDRAWN: a naive prefix matcher said 562 hook-ask
commands were also allow-covered, but Claude Code evaluates each statement of a
compound command, so those were `cd`-prefix artifacts. Restricted to single-statement
commands the overlap is 0 of 16 — the corpus cannot settle it. Hence the live probe.

## What settings.json can actually buy
Approximating CC's statement split, and requiring EVERY statement to be covered:
  Bash(curl:*)    +323
  Bash(sed:*)      +15
  Bash(timeout:*)   +4
  Bash(bash:*)      +2
  Bash(awk:*)       +1
Baseline check: 0 of the 1,655 clear under today's rules — which is exactly right,
since every one of them did prompt. The splitter does not over-clear.

The remaining ~1,300 curl prompts are compound (`for u in …; do curl …; done`) and no
allow rule can express them.
