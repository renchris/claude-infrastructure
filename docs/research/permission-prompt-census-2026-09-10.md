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

## The curl "hook-raised" premise expired on 2026-08-23

`docs/research/permission-harvest-hook-ceiling-2026-09-10.md` §"curl" excludes curl from the
hook-layer ceiling because "curl is hook-raised, measured: 1,367 of 1,368 curl 'gap' rows joined
to a `curl-gate` ask within ±15 s", and `permission-harvest-completion-2026-09-11.md` §4 carries
that forward into the closing verdict — the three greedy picks `rm` → `git` → `curl` are "all
already owned by existing guards", leaving 1.9 %, so `proposed=0` is the correct steady state and
"nothing in §§1-12 names an outstanding unit".

That join is against what curl-gate did AT PROMPT TIME. This census replays TODAY's gate over the
same archive. Both are correct about different binaries, and a landed fix separates them:
`d8b517b28` (2026-08-23) — "the gate spent 1,822 prompts on its own parser and 370 hard blocks on
the word cd". Split at that date, replayed through today's curl-gate:

  pre-fix  (<2026-08-23):  660 curl-bearing prompts — 641 get NO hook decision, 17 ask
  post-fix (>=2026-08-23): 1123 curl-bearing prompts — 896 get NO hook decision, 204 ask

~86 % of curl prompts are not hook-raised today. They are raised by the RULE layer, because there
is no `Bash(curl:*)` allow rule — which is the layer the exclusion also removed curl from, since
"already owned by a guard" was the reason for both.

WHAT THIS DOES AND DOES NOT CLAIM. It does NOT refute the ≤1.9 % hook-ceiling headline, and it does
not re-open the completion note by itself: the two populations may not be identical (theirs is a
filtered "gap" subset; mine is every archived Bash prompt whose command bears `curl`), and I did not
reconcile the denominators. What it claims is narrower and sufficient: **the specific premise that
removed curl from consideration is a property the gate LOST on 2026-08-23, so it needs re-measuring
before `proposed=0` is inherited as settled.** Re-derive with the instrument that note ships —
`python3 docs/research/permission-harvest-hook-ceiling-2026-09-10/hook-ceiling.py` — after
restricting the archive to prompts at or after 2026-08-23; its own header says every figure decays
with the archive at ~40 rows/day, which is exactly the decay observed here (MEMORY.md
published-figure-decays-with-its-source).

The 323 whole-command-clearable figure in §"What settings.json can actually buy" above is a HAND
estimate from an approximate statement splitter and has been through none of `cc-permission-harvest`'s
eleven refutation gates. Run the `permission-harvest` skill before adding any rule; do not treat
that number as a proposal.
