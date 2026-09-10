# Three 5h limits in 90 minutes — 2026-09-10

**Answer.** On `next`, the limit was a recovery cascade: at 13:16:54–13:17:02Z `/limit-recover`
arrived in ~13 panes across all four accounts inside 8 seconds, and the Fable 5.1 sessions on `next`
obeyed its step 3 — resume every interrupted Workflow and re-run its dangling slots — all at once. One
research workflow consumed `next`'s whole 5h window and then lost 74 of its 92 re-run slots to the
limit it had just caused. On `next3` and `next4` the meter rose just as fast, but **local transcripts
do not account for it** (see §3); that half is unexplained.

## 1. Timeline (utilization samples, `~/.claude/logs/account-utilization.jsonl`)

| account | burst | 5h | weekly |
|---|---|---|---|
| next4 | 12:47→13:05Z, window reset 13:09, then 13:12→13:41Z | 12→58%, then 4→100% | 43→64% |
| next  | 13:22→13:50Z | 23→100% | 64→84% |
| next3 | window reset 14:00, 14:14→14:28Z | 40→100% (+41pp in 5 min) | 31→49% |

Before 12:47Z every account moved ~1pp per 10 minutes.

## 2. Where `next`'s spend went (deduped on `message.id`, 11:00–14:45Z)

Quota-bearing tokens per 15-min bucket on `next`: 13:15 → 5.25M, 13:30 → 5.03M, ~3.8M of each on
`claude-fable-5-1`. Ranked by weighted cost (output×5 + cache-write×1.25 + input, Fable ×2):

| session | share of fleet cost | what it did | outcome |
|---|---|---|---|
| `7193ec2b` (wt-pool-3, Fable 5.1 max) | 39% | `/limit-recover` → resumed `wf_bfe66728` ("memory system for the three warm leads"): 92 slots ran, 537 Fable calls, 5.24M cache-write, 10k output; **74 slots ended on the limit** | 0 commits; run reported "completed" over the dead slots |
| `2d71c6d8` (hammerspoon, Fable 5.1 max) | 20% | two resumes of `wf_bc4b9e69`, 3 deep-research re-runs, a new workflow; 16 of 18 slots ended on the limit | 1 push |
| `6b8b69c2` (wt-pool-2, Fable 5.1 max) | 4% | one slot, 514k cache-write, 0 output | none |

The three Fable workflow sessions are 63% of the fleet's weighted cost in the window. Output was
negligible everywhere (0.13M on `next`); the cost is cache writes of 250–750k-token contexts, paid
once per slot and once per cold resume.

## 3. `next3` / `next4`: not explained by anything on this machine

In its 14:05–14:30Z spike `next3`'s store holds 8 assistant messages (~1.5M cache-read, ~6k
cache-write) against +60pp 5h / +18pp weekly; `next2` moved ~2pp weekly over three hours of far
heavier local traffic. Ruled out, each measured:

- env OAuth tokens — no live `claude` process carries `CLAUDE_CODE_OAUTH_TOKEN`; all bill by config dir
- a second transcript store — no other `~/.claude*` dir was written 13:00–14:40Z
- plan size — all four `.claude.json` read `default_claude_max_20x`
- local headless `claude -p` — none live, none logged in the window
- the six extra `next3` processes — Claude Code's own `daemon run` / `bg-spare` pre-warm, started 05:49Z

Not excluded: off-box use of those accounts, and cloud session `session_01MvTEDY…` fired 12:31Z,
16 minutes before `next4`'s burst, whose record carries no account field.

## 4. Two defects in the reset poller (fixed on `fix/lr-poller-lrp-self`)

1. **`next` was never scanned.** The detect pass ran `find "$cfg/projects"`; `~/.claude-next/projects`
   is a symlink to `~/.claude/projects` and BSD `find` does not descend a symlinked start without
   `-H` (0 transcripts vs 123). Over the poller's whole history: 17 `next2`, 42 `next3`, 4 `next4`,
   **0 `next`** parks. `scripts/boot-resume.sh:159` had the same lookup. Both now `find -H`.
2. **`_LRP_SELF` read before assignment.** The lr-lib ladder read it ~190 lines before it was set.
   `set -u` killed only the `$(dirname …)` subshell, so every tick still exited 0 while printing the
   error (160 lines in `poller.launchd.err`) and losing the symlink-resolved rung.

Left alone deliberately: `scripts/cc-gc.sh:416` and `bin/cc-mailbox-alias-gc:80` share the
symlink-blind `find`, but both are garbage collectors — adding `-H` would start deleting in `next`'s
store, a behaviour change outside this fix.

## 5. The hazard the fix creates

The poller's in-place recovery types `/limit-recover` into the pane (`lr-reset-poller.sh`
`nudge_in_place`). With `next` now visible, its six limited sessions become nudgeable at the 16:40Z
reset, four per 10-minute tick — including `7193ec2b`, whose 74 dead Fable slots are exactly what
`/limit-recover` re-runs. `next` has 16pp of weekly left until Sat 22:59 local; the last re-run of that
workflow moved `next`'s weekly by ~20pp.
