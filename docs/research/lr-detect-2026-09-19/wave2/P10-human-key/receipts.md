# P10-human-key — receipts

Unit: is the human-meaningful key (conversation title) available without the screen?
All commands run 2026-09-19, read-only. Box: 15 kitty windows, 13-14 live registered panes.

VERDICT: **HOLDS, with a bounded coverage gap.** The title is on disk, it is stable, it sits
inside the 128 KB tail the prototype already reads, and it agrees 13/13 with what kitty shows.
It covers 11 of 13 live panes and 12 of 15 of today's limit deaths; the sessions it misses are
dispatched/woken panes, and NO existing surface carries a human key for those.

---

## R1 — the record shape, and it is stable

```
$ f=~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/c301b7a5-...jsonl
$ grep -n -m1 'ai-title' "$f"
38:{"type":"ai-title","aiTitle":"MCP assets migration before deprecation","sessionId":"c301b7a5-0133-4482-9f45-c7ce9b888c4d"}
```

Three fields only: `type`, `aiTitle`, `sessionId`. **No pane id, no account, no cwd.**

Stability, over the 30 titled transcripts among the 40 most-recently-modified:

```
$ while read f; do c=$(grep -o '"aiTitle":"[^"]*"' "$f"|sort -u|wc -l); n=$(grep -c ai-title "$f"); ...
distinct=1 records=104 59ed2093
distinct=1 records=83  eda3a683
... (30 rows, every one distinct=1) ...
distinct=1 records=15  79eb53b5
```

**30/30 have exactly ONE distinct title, repeated 15–104 times.** The title never drifts
mid-session, so any occurrence answers the question — "read the last one" is a cheapness
choice, not a correctness one.

## R2 — WHEN it updates: once per prompt submission

```
$ python3 ... Counter of record types in c301b7a5 (841 lines)
[('assistant',247),('attachment',194),('user',125),('last-prompt',41),('mode',41),
 ('permission-mode',41),('atis-latch',41),('bridge-session',41)]
total ai-title: 40
38 ai-title prev= bridge-session
49 ai-title prev= last-prompt
70 ai-title prev= last-prompt
91 ai-title prev= last-prompt
```

A six-record meta block `{last-prompt, ai-title, mode, permission-mode, atis-latch,
bridge-session}` is appended at **every user prompt submit** (41 blocks, 40 titles — the first
block predates titling). Staleness of a tail read is therefore bounded by ONE turn.

## R3 — THE DECISIVE ONE: the title is already inside the 128 KB tail

Distance from the LAST `ai-title` record to EOF, all 30 titled transcripts of the recent-40 set:

```
$ while read f; do tot=$(wc -c <"$f"); ln=$(grep -n ai-title "$f"|tail -1|cut -d: -f1);
  by=$(head -n "$ln" "$f"|wc -c); echo "$((tot-by)) $(basename $f)"; done | sort -n
1018 59ed2093
3216 19f6b94b
...
33389 67d02a41
n=30
```

**max = 33,389 bytes; 30/30 under 33.4 KB.** The prototype's existing 128 KB tail read already
contains it — the title column costs **zero additional I/O and zero additional forks**.

Contrast the HEAD: the *first* ai-title sits at line ~38 but **400 KB–1.1 MB into the file**
(measured: `line=38 byte=562766`, `line=48 byte=784590`, `line=89 byte=1097865`). A head read is
the wrong instrument; a tail read is the right one, and we were already doing it.

## R4 — it works on the real population: today's limit deaths

```
$ for sid in <8 sids from ~/.claude/autonomy/stop-failure/rate_limit__next3.jsonl>; do
    f=$(find ~/.claude*/projects -maxdepth 2 \( -name "$sid*.jsonl" -o -name "$sid*.jsonl.handed-off" \) | head -1)
    tail -c 131072 "$f" | grep -o '"aiTitle":"[^"]*"' | tail -1; done
98f02458 "W1b floor-plan first frame soft nav"
09e64dcb "API key export silver platter"
11569d45 "/limit-recover optimization and investigation"
65186f1f "Subagent lifecycle root cause implementation"
8843bcf3 "Weekly limit exhaustion display"
4bc1159f "reso-management-app worktree sync strategy"
26cd14be "Kitty Terminal split pane auto-even on move"
07e30aeb "Bottle image review for Studio60 menu"
```

**8/8 on next3.** next4: 4/7 (`Image #1`, `Pyramid Principles implementation status`,
`API key export silver platter`, `Git-forest integration evaluation`; 3 untitled).
**12/15 overall.**

Note `Image #1` — a degenerate title produced when the first prompt was a pasted image. The
column must tolerate a useless-but-present title; it is not a failure mode to code around.

## R5 — the marker's `transcript_path` is a snapshot and is usually DEAD

```
$ python3 ... os.path.exists(marker['transcript_path']) for rate_limit__next3.jsonl
0 98f02458 False   3 11569d45 False   7 65186f1f False
1 09e64dcb True    4 11569d45 False   8 8843bcf3 True
2 11569d45 False   5 65186f1f False   9 4bc1159f False ...
```

**9 of 12 marker rows point at a path that no longer exists** (the transplant renames the file
to `.jsonl.handed-off`). The resolver MUST glob `<sid>.jsonl` ∪ `<sid>.jsonl.handed-off` across
all five config dirs, not trust the marker's path.

Worse — one sid, three files, two config dirs:

```
$ find ~/.claude*/projects -maxdepth 2 -name '07e30aeb*.jsonl*' | while read f; do echo "$(wc -c <"$f") $(grep -c ai-title "$f") $f"; done
1157520 8 .claude-secondary/.../07e30aeb-....jsonl
   2886 0 .claude-tertiary/.../07e30aeb-....jsonl          <- the resumed successor: EMPTY, untitled
1157520 8 .claude-tertiary/.../07e30aeb-....jsonl.handed-off
```

Picking the first match returns `NONE` for a session that plainly has a title. **Order candidates
`(.handed-off last, size descending)` and take the first that yields a title.** The
`<sid>.HANDOFF.json` sidecar is the authoritative pointer for the move
(`{handed_off_to, target_transcript, ts, lock}` — 333 bytes, no human label of its own).

## R6 — coverage, honestly: 72% of 24-h transcripts, 85% of live panes

```
$ python3 /tmp/p10_tailtitle.py     # single process, 128 KB tail, no forks
files=57 titled=41 untitled=16 elapsed_s=0.007
```

Whole corpus, brute force, as an upper bound:

```
$ python3 /tmp/p10_all.py
files=2174 titled=1416 enumerate_s=0.353 read_s=0.237 total_s=0.591
```

**0.59 s for 2,174 transcripts** against `lr-fleet.sh --locate`'s measured 35.5 s — a 60× floor
even before targeting. The targeted version (13 named sessions) resolves in **3 ms**:

```
$ python3 /tmp/p10_census2.py
index_build_s=0.098 resolve_s=0.0027 total_s=0.100 panes=13 titled=11 index_sids=2183
```

The untitled set is NOT explained by "too early":

```
$ python3 /tmp/p10_untitled.py      # prompts submitted vs title, untitled transcripts, last 24h
prompts= 66 bytes=5232309 28f07827 worktrees-wt-cc-100046-36511
prompts= 38 bytes=2347460 05683f40 worktrees-wt-cc-100046-36511
prompts= 22 bytes=2730199 12e163a9 claude-infrastructure
prompts= 14 bytes=1311642 1b6e5b11 claude-infrastructure
prompts= 10 bytes= 905478 74de0b05 claude-infrastructure
... prompts=0..6 for the remaining 11 ...
```

`28f07827` submitted **66 prompts** over 5.2 MB and emitted **67 bridge-session blocks with zero
ai-title**. So titling is a server-side generation that can simply never run for a session; it is
not a function of session length. Every long untitled session in this sample sits in a
`wt-cc-*` dispatched-fire worktree or in the shared `claude-infrastructure` checkout.
**UNMEASURED:** whether dispatched fires are systematically untitled. Falsifier: sample 20
`wt-cc-*` sessions with >=10 prompts and count titles; if >=half are titled, the correlation dies.

## R7 — the FTS session-index is USELESS for live sessions (REFUTES it as a source)

```
$ sqlite3 ~/.claude/session-index.db "select source,count(*),sum(first_prompt=''),sum(summary='') from sessions group by source;"
history|3737|0|3737
history-legacy|358|0|358
session-start|615|506|615
session-sweep|20|0|20
sessions-index|1913|488|1913
transcript|39|0|39
```

`summary` is empty for **all 6,682 rows**. `source=session-start` is 615 rows of which **506
(82%) have an empty `first_prompt`**. And for the exact sessions the census needs:

```
$ sqlite3 ... where session_id like '<each of today's 8 next3 sids>%'
09e64dcb|sessions-index|0||2026-09-19T17:26:26Z
4bc1159f|sessions-index|0||2026-09-19T20:59:37Z
26cd14be|sessions-index|0||2026-09-19T20:57:57Z
11569d45|session-start |0||2026-09-19T20:57:01Z
65186f1f|sessions-index|0||2026-09-19T20:48:39Z
98f02458|sessions-index|0||2026-09-19T20:53:29Z
8843bcf3|session-start |0||2026-09-19T21:02:19Z
07e30aeb|session-start |0||2026-09-19T19:32:10Z
```

**8/8 present, 8/8 with `length(first_prompt)=0`.** `keywords`, `tags`, `search_aliases`,
`context_text` are all length 0 too; only `project_name` is populated, which the registry's `cwd`
already gives. A 104 MB database that answers the census's question zero times out of eight.

## R8 — kitty: the title IS the ai-title, and the per-pane `--match` idea is 12x worse

```
$ kitten @ ls   (15 windows, 166 KB)
id=126 title=* MCP assets migration before deprecation        cwd=claude-infrastructure
id=110 title=* reso.gl money-path latency fix                 cwd=reso-web-app
id=127 title=( /limit-recover optimization and investigatio   cwd=claude-infrastructure
id=147 title=* Bottle image review for Studio60 menu          cwd=reso-management-app
id=114 title=) Claude Code                                    cwd=wt-cc-100046-36511   <- untitled session
id=122 title=chrisren@Chriss-MacBook-Pro-3:~/Development/cl   cwd=claude-infrastructure <- plain shell
```

(leading glyph is one of the Claude Code spinner marks, rendered here as `*`/`(`/`)`.)

The window title is `<spinner glyph> <aiTitle>`; it degrades to the literal `Claude Code` for
exactly the sessions that have no `ai-title` (id=114 = `05683f40`, the 38-prompt untitled one).
**The glyph is NOT a limit signal** — today's limited sessions carry all three glyphs alike.

Latency A/B, 5 reps each, timed inside one python process (honest subprocess accounting):

```
full_ls     min/avg/max s: 0.027 0.029 0.031
per_pane_15 min/avg/max s: 0.338 0.347 0.380
```

**One unmatched `kitten @ ls` = 29 ms for the whole fleet; `--match id:N` x15 = 347 ms.**
The premise's per-pane read is 12x more expensive and returns strictly less. (The brief's
"~37 ms per match / ~0.5 s unmatched" is not reproduced: 23 ms per match, 29 ms unmatched.)

kitty carries **no session id** — `window.env` has zero `CLAUDE_*` keys and `user_vars` is empty
on all 15 windows. The join must come from the registry.

## R9 — the registry join is exact, and the registry CANNOT carry the title

`~/.claude/cc-registry/<paneUUID>.json` is keyed by the **kitty window id**, so the join is free:

```
 126 c301b7a5 claude-next        claude-infrastructure   <-> kitty id=126 "MCP assets migration..."
 111 09e64dcb claude-tertiary    claude-infrastructure   <-> kitty id=111 "API key export silver platter"
 147 07e30aeb claude-tertiary    wt-cc-143039-68221      <-> kitty id=147 "Bottle image review..."
 114 05683f40 claude-secondary   wt-cc-100046-36511      <-> kitty id=114 "Claude Code"
```

Who would write a title field, and when:

- `hooks/session-register.sh` is the **sole writer** and runs on **SessionStart only**
  (`~/.claude/settings.json` hooks: `SessionStart | | ~/.claude/hooks/session-register.sh`). The
  other 20 files that mention `cc-registry` read it; `session-deregister.sh` deletes.
- The write is a **whole-row atomic overwrite** (`hooks/session-register.sh:282-291`,
  `jq -n ... > "$tmp"; mv -f "$tmp" "$reg_dir/$pane.json"`), so a later writer would have to
  re-read and merge, not append.
- The title **does not exist at SessionStart** — it first appears at the 2nd prompt block at the
  earliest (R2), and never at all for some sessions (R6).

So a registry title field would need a NEW writer on `UserPromptSubmit`/`Stop`, which would have
to read the transcript anyway. **It would be a cache of a 0.2 ms read. Do not build it.**

## R10 — cross-instrument agreement: 13/13

```
$ python3 /tmp/p10_agree.py
panes=13 agree=13 disagree=0 transcript_path_s=0.532 kitty_ls_s=0.031
```

Transcript-tail title and kitty window title agree on **every live pane**, including agreeing on
absence (transcript `None` <-> kitty `Claude Code`). Two independent instruments, zero
disagreements.

## R11 — the fallback ladder, measured, including where it fails

```
$ python3 /tmp/p10_best.py     # kitty-first, transcript fallback
 110 c0f857b6 next        kitty       reso.gl money-path latency fix
 111 09e64dcb tertiary    kitty       API key export silver platter
 114 05683f40 secondary   cwd         (untitled) wt-cc-100046-36511
 143 fff83638 quaternary  cwd         (untitled) wt-cc-142546-79030
 158 12e163a9 quaternary  cwd         (untitled) claude-infrastructure
 ... 11 more, all via kitty ...
# registry_s=0.0013 kitty_s=0.031 join_s=0.00002 fallback_s=0.102 TOTAL=0.134 n=14 via_kitty=11
```

Rung 3 (first human prompt) is weak exactly where rung 1 fails:

```
$ python3 /tmp/p10_first.py <three untitled transcripts>
05683f40 bytes_read=2005145 3.0ms :: None
12e163a9 bytes_read=2000015 3.7ms :: None
fff83638 bytes_read=  75084 0.1ms :: Re-up our bottle service review page and let's pick up where we were for our bottle image review, I
```

`05683f40`'s first user record is `<task-notification> <summary>peer mail</summary>` — a machine
wake, not a human prompt. Dispatched/woken sessions have no human first prompt either.

Rung 4 (cwd basename) is always present but barely discriminates:

```
live panes: 13   distinct cwd basenames: 9   collisions: {'claude-infrastructure': 5}
```

against **11 distinct titles for 11 titled panes — 100% unique.**

The StopFailure marker cannot help: its `last_assistant_message` is the limit banner itself on
**25/25 rows** (`"You've hit your session limit - resets 4:30pm (America/Chicago)"`), carrying
zero task identity. It does pin the account's reset time, which is a different column.

## R12 — the resolver, and what it must refuse on

```
$ python3 /tmp/p10_resolve.py bottle limit-recover 149 xyzzy claude-infrastructure
q='bottle'                verdict=OK         n=1 us=7
    pane 147 07e30aeb tertiary   Bottle image review for Studio60 menu
q='limit-recover'         verdict=AMBIGUOUS  n=2 us=5
    pane 127 11569d45 secondary  /limit-recover optimization and investigation
    pane 150 7f533f05 quaternary limit-recover optimization
q='149'                   verdict=EXACT      n=1 us=2
q='xyzzy'                 verdict=NO-MATCH   n=0 us=5
q='claude-infrastructure' verdict=AMBIGUOUS  n=5 us=5
```

2–7 microseconds per query over the in-memory census. The ambiguity is real and not pathological
— two live sessions are genuinely doing "limit-recover optimization" right now — which is exactly
why the resolver must print the candidates and refuse rather than pick.

---

## THE DELIVERABLE

**Cheapest correct `title` column**, first hit wins:

| rung | source | cost | coverage (live panes) |
|---|---|---|---|
| 1 | kitty window title, glyph-stripped, `!= "Claude Code"` and not a shell prompt | **29 ms once, whole fleet** | 11/13 |
| 2 | last `"aiTitle"` in the 128 KB tail of `<sid>.jsonl`, then `<sid>.jsonl.handed-off`, ordered size-desc | **0.2 ms/file**, bytes already read | + non-pane / transplanted cases |
| 3 | first non-meta, non-`<tag>`-framed user text (head scan, cap 2 MB) | 0.1–3.7 ms | human-started sessions only |
| 4 | `(untitled) <cwd basename>` + `sid8` from the registry | 1.3 ms for all rows | always, but 5-way collisions |

Rung 1 goes first only because the census already calls kitty for pane liveness; rung 2 is the
**authority** (it is what rung 1 displays) and is the only rung that works for a session with no
pane. Measured end-to-end for a fully-titled 14-pane census: **0.134 s**, of which 0.102 s is a
directory walk that disappears when the sid->path index is built once per census rather than per
rung.

**Resolver contract** — `lr <query>`:

1. exact `pane` id or `sid` prefix => EXACT, resolve.
2. else case-insensitive substring over `title`, then over `cwd` basename.
3. exactly one hit => resolve. zero => `NO-MATCH`. **two or more => REFUSE**, print
   `pane · sid8 · account · title` for each and exit non-zero. Never pick by recency — the two
   "limit-recover" panes differ by account, and guessing the account is the expensive mistake.
4. A row whose title came from rung 4 is marked `(untitled)` in the output, so the operator can
   see that the key they matched on is a directory, not a description.

**Do not build**: a title field in `cc-registry` (R9 — a cache of a 0.2 ms read, needing a new
hook writer); a title lookup through `session-index.db` (R7 — 0/8 on the live population); a
per-pane `kitten @ ls --match id:N` loop (R8 — 12x the cost of one unmatched `ls`).

**Residual gap, named**: dispatched/woken sessions (`wt-cc-*` fires) can reach 66 prompts with
neither an `ai-title` nor a human first prompt. No surface on disk carries a human key for them.
The cheap close is at the FIRE, not at the census — `handoff-fire.sh` already holds a
human-meaningful `--goal` string and a brief path, and stamping that label onto the pane (a kitty
`user_var`, **empty on all 15 windows today**, therefore free) would give those sessions a key at
zero read cost. That is a recovery-chain dependency, so it is named here and not specified.
