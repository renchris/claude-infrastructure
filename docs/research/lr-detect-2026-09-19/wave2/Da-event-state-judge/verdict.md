# JUDGE — Da-event-state · lens: CORRECTNESS + FAULT-VISIBILITY · 2026-09-19 · score 4.5/10

## Measurement that drives the verdict (run this session, read-only)

### M1 — the uuid latch is backwards: 8 of 10 multi-fire sids re-cap, they do not latch
`python3` join of `~/.claude/autonomy/stop-failure/rate_limit__*.jsonl` fires against every
glob-resolved `<sid>.jsonl*` copy (realpath-deduped), counting DISTINCT `type==assistant ∧
error=="rate_limit"` uuids:

| sid8 | marker fires | distinct rate_limit uuids | shape |
|---|---|---|---|
| e442434c | 4 (16:58:33/43/49, 17:27:19) | **4** (76079a2e 57ec86da 3f08d075 8c05ccc3) | RE-CAP ×4 |
| 28f07827 | 4 | **4** | RE-CAP ×4 |
| 12e163a9 | 4 (21:39:13→:17, **4 s**) | **4** | RE-CAP ×4 |
| 09e64dcb | 3 | **3** | RE-CAP ×3 |
| eb77ca3e | 3 | **3** | RE-CAP ×3 |
| 75c7e2a5 | 3 | **3** | RE-CAP ×3 |
| 98f02458 | 2 | **2** | RE-CAP ×2 |
| 65186f1f | 2 | **2** | RE-CAP ×2 |
| 11569d45 | 3 (19:53:44/45/50) | **1** (ad6ea5d2 @ :50) | latch on a BOGUS key |
| 7f533f05 | 11 (21:35:29→:53) | **1** (3792dd7d @ :53) | latch on a BOGUS key |

§4.4 claims the uuid latch "collapses e442434c's 3 fires in 16 s". Measured: those 3 fires carry
3 DIFFERENT uuids ⇒ 3 full re-caps. The latch fires only in the 2 cases where the api-error
record had not yet been flushed at hook time — i.e. where the fallback key is used.

### M2 — pre-`:130` exits that arm 2 sits below
`hooks/stop-failure-marker.sh:115-117` `if [ "$LINES" -ge "$CAP" ]; then log_idl passed
"marker-capped"; exit 0; fi` (CAP=500, `:42`); `:96` `mkdir -p "$MARKER_DIR" ||
_sf_abstain "marker-dir-unwritable"`; `:64/:65/:66/:79` abstains. Da §5.1: "Everything above
`:130` is byte-identical." Db-derive-on-read §4.3 inserts its arm **BEFORE the cap early-exit at
`:115`** — the sibling design got this right.
Cap reachability: `wc -l rate_limit__next4.jsonl` => **36 lines / 12 sids in ONE day**; TTL prunes
only a file untouched 1440 min, so a daily-capping account accumulates to 500 in ~2 weeks.

### M3 — `lr_last_api_error` rc 1 is "the LAST assistant record is not an api error"
`scripts/limit-recover/lr-lib.sh:129, :144-146`. Prints 4 tab fields today (`:155-158`).

### M4 — account spellings / symlink
`jq .accounts[]` => next/next2/next3/next4 only; **no `~/.claude` row**. Registry rows carry the
basename spelling (`claude-quaternary`). `readlink ~/.claude-next/projects` =>
`/Users/chrisren/.claude/projects` — one physical tree under two config dirs.
`rate_limit__.claude.jsonl` naming is live-exercised (`authentication_failed__.claude.jsonl`).

### M5 — the repo's own census lesson
`docs/lessons/census-matches-itself.md:5`: "the test that catches both is the NEGATIVE one: ask the
census about an identifier nothing holds and require rc 1. Every positive case passes either way."
Da §11.3 gives NO-MATCH **exit 1**, the same code §11.2 assigns to "≥1 session needs recovery".

### M6 — sound, verified
`scripts/lib/spawn-presence.sh:319` selects `.kind == "prompt"`; `hooks/session-beat.sh:58` takes
kind from `$1` with no enum validation, `:62` skips `who` for non-prompt. §6 holds.
Transplant preserves the sid: `7f533f05-…jsonl.handed-off` under `~/.claude-quaternary` and
`…jsonl` under `~/.claude-tertiary` — same basename. The `moved` overlay's key is sound.
