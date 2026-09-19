# P5 — registry coverage for the pane->sid join

Measured 2026-09-19 20:53Z–21:05Z on the live box. Box local = UTC-5 (CDT) — `date; date -u`
=> `Sat 19 Sep 2026 15:55:49 CDT` / `Sat 19 Sep 2026 20:55:49 UTC`. All scripts under this dir.

PREMISE: "the registry (~/.claude/cc-registry) is complete and live-correct for the pane->sid join."
VERDICT: **PARTIAL** — live-correct is CONFIRMED and strong; COMPLETE is REFUTED.

---

## R1 — the census rule, and its cost

`rule.py` (this dir). Rule = `registry rows` ∩ `kill -0 pid` ∩ `lstart(row) == lstart(ps)`,
with `TZ=UTC LC_ALL=C` on the `ps` read (the writer uses the same, `hooks/session-register.sh:278`).

Three consecutive runs (`rule1.json`..`rule3.json`):

```
1 {'registry_read': 0.9, 'ps': 32.4, 'rule': 0.0, 'kitty_ls': 29.0, 'total_no_kitty': 33.3, 'total': 62.3} rows 32 live 14 dead 18
2 {'registry_read': 1.0, 'ps': 30.8, 'rule': 0.0, 'kitty_ls': 28.2, 'total_no_kitty': 31.8, 'total': 60.0} rows 32 live 14 dead 18
3 {'registry_read': 1.0, 'ps': 31.2, 'rule': 0.0, 'kitty_ls': 28.3, 'total_no_kitty': 32.1, 'total': 60.4} rows 32 live 14 dead 18
```

**32 ms** for the whole pane↔sid↔liveness census (1 ms of file reads + one `ps` fork); the
`kitten @ ls` cross-check adds 28 ms for 60 ms total. Against `lr-fleet.sh --locate` at 35.5 s
this is ~1,100x. The rule itself costs 0.0 ms — the entire budget is one `ps`.

## R2 — live-correctness: 14/14, zero defects in every class the unit named

`census.py` => `census1.json`, 0.13 s:

```
registry_rows 32 | live_claude_pids 14 | live_ok 14 | dead_pid 18
lstart_mismatch = []   pid_not_claude = []   no_lstart = []
paneUUID_null   = []   sid_null      = []    dup_sids  = {}
live_claude_no_row = []
```

The 14-process denominator is exhaustive, not a filter artifact:
`ps -eo command= | awk '{print $1}' | grep -i claude | sort | uniq -c`
=> `14 /Users/chrisren/.claude-260/node_modules/.bin/claude` — one argv0 on the box, 14 of it.

Kitty cross-check (`rule3.json`): `live_not_in_kitty: []`, `kitty_not_registered: ["140"]`,
and 140 is a bare shell, not a session —
`kitten @ ls --match id:140` => `id 140 ... fg [['/bin/zsh', '-l']]`. So deregistration on clean
exit works; the row was removed and the window survived.

## R3 — row→transcript join: 31/31 correct on BOTH account root and cwd slug

`join2.py` => `join2.json`, 0.14 s. Checks each row's `session_id` against the transcript index
built over the 4 REAL project roots (`.claude` and `.claude-next` share one —
`readlink -f ~/.claude-next/projects` => `/Users/chrisren/.claude/projects`), asserting the file
lives under the root implied by `row.account` and in the dir implied by `row.cwd`:

```
ok 32 missing 0 mismatch 0 scan_s 0.139
```

Re-run 10 min later incl. the `.handed-off` namespace:
`rows 31 | sid->live transcript 31 | sid -> ONLY .handed-off: [] | sid -> NO transcript: []`
(47 `.jsonl.handed-off` files exist fleet-wide; no live row points at one).

CAVEAT on the slug: it is `[./_] -> '-'`, not just `/`. A naive `p.replace('/','-')` reports
**32 of 32 rows as mismatched** — a clean, confident, entirely false negative finding.

## R4 — COMPLETENESS IS REFUTED: 3 of 14 of today's rate_limit sessions have NO row

The target population, joined directly (`~/.claude/autonomy/stop-failure/rate_limit__*.jsonl`
× registry):

```
NOROW  e442434c markers=['next4'] n=4 first=2026-09-19T16:58:33Z last=2026-09-19T17:27:19Z
NOROW  28f07827 markers=['next4'] n=4 first=2026-09-19T17:07:35Z last=2026-09-19T17:14:48Z
NOROW  98f02458 markers=['next3'] n=2 first=2026-09-19T19:52:33Z last=2026-09-19T19:57:43Z
... 11 others resolved to a pane row ...
rate_limit sids=14 agree=7 disagree=4 no_row=3
```

98f02458 is not a stub — 3.0 MB, `entrypoint: cli`, and its LAST record is the cap itself:

```
tail -1 ... => {"type":"system","subtype":"turn_duration",...,"timestamp":"2026-09-19T19:57:42.975Z"}
prev        => assistant, model "<synthetic>", "You've hit your session limit · resets 4:30pm (America/Chicago)"
grep -c 'hit your session limit' => 2
```

A registry-keyed census is blind to 21.4% of the exact sessions this project exists to find.

## R5 — the wider completeness number: 14 of 44 sessions today have no row

Transcripts modified today vs registry (`join`-style scan, 0.10 s):

```
transcript files 2172 | distinct sids 2163
sids touched TODAY: 43   of which in registry: 30 (69.8%)
today sids >200KB:  41   of which in registry: 30
```

Classified (age, root, size, `entrypoint`, cwd, panes already registered at that cwd):

```
  0.3h 26cd14be .claude-secondary   2810KB cli     ~/Development/claude-infrastructure       -> panes@cwd [103,158,122,129,128,104,149,127,111,126,117]
  0.3h 98f02458 .claude-secondary   2994KB cli     ~/Development/.worktrees/wt-pool-2        -> panes@cwd [123,133]
  1.1h dac29229 .claude-secondary   2939KB cli     ~/Development/.worktrees/wt-pool-5        -> panes@cwd []
  1.2h 4bbf5d65 .claude-tertiary    1437KB cli     ~/.../fix/it2-kitty-composer-guard-narrow -> panes@cwd [134]
  1.5h 1d6573a9 .claude-secondary    918KB cli     ~/.../wt-cc-142813-68221                  -> panes@cwd []
  1.5h ab2b6cde .claude              923KB cli     ~/.../wt-pool-8                           -> panes@cwd []
  1.9h 002a6527 .claude-tertiary    3365KB cli     ~/.../wt-pool-3                           -> panes@cwd []
  2.7h 28f07827 .claude-secondary   5109KB cli     ~/.../wt-cc-100046-36511                  -> panes@cwd [114]
  2.9h e442434c .claude-tertiary    4746KB cli     ~/Development/claude-infrastructure       -> panes@cwd [...]
  3.9h 21446ede .claude              828KB cli     ~/Development/claude-infrastructure       -> panes@cwd [...]
  4.4h 23ee8ab5 .claude-quaternary  5091KB cli     ~/Development/sevenrooms-bridge           -> panes@cwd []
  6.2h 8f0df3c9 .claude-tertiary     990KB cli     ~/.../wt-cc-235742-75429                  -> panes@cwd []
 11.6h e9561f51 .claude               46KB sdk-cli ~/Development/reso-qa-runner              -> panes@cwd []
 11.7h 7c81d279 .claude               51KB sdk-cli ~/Development/reso-qa-runner              -> panes@cwd []
uncovered today: 14
```

Two mechanisms, both structural, both in `hooks/session-register.sh`:

1. **Keyed by pane, one row per pane.** `"$reg_dir/$pane.json"` (`:165` + the jq write at `:282-288`). A pane that runs
   session A then B keeps only B. Confirmed by direct observation: 23ee8ab5 (sevenrooms-bridge,
   5.1 MB, no row) is named in the argv of live pid 95369 as the predecessor that recycled into
   pane 110's current sid c0f857b6 — `ps -eo command=` on 95369 contains
   `"session 23ee8ab5-5628-485f-a250-3b58ecebeb04): ... recycled"`.
2. **No address ⇒ no row.** `pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"` … `case "$pane" in ''|.|..)
   return 0` (`hooks/session-register.sh:127-133`). The 2 `sdk-cli` rows are this class by design.

## R6 — 56% of rows are STALE, and `kill -0` alone is NOT sufficient

18 of 32 rows have a dead pid (`rule*.json` `dead`), incl. the two the unit named (143, 145) plus
103/104/107 from Sep 18 (age 21–23 h). Clean exits ARE deregistered (R2, pane 140), so a stale row
means an ABNORMAL exit — which is exactly the limit/crash population.

The `lstart` clause is load-bearing, and the archive proves it:

```
cat ~/.claude/cc-registry/580.json.stale-1787629385
  {"paneUUID":"580","pid":1347,"session_id":null,"surface":"headless",
   "lstart":"Tue Aug 25 03:18:32 2026", ...}
TZ=UTC LC_ALL=C ps -o pid=,lstart=,comm= -p 1347
  1347 Wed Sep 16 21:29:15 2026  /Users/chrisren/.cursor/extensions/ms-python.python-.../bin/pet
```

`kill -0 1347` => alive (exit 0). The row is 617 h old and its pid now belongs to a Cursor helper.
**(pid, lstart) is the identity; pid alone false-positives.** That row also carries
`session_id: null` — the null-sid class exists, only in the archived/provisional namespace
(4 more: `48.json.stale-*`, none of which carry a `surface` field at all).

## R7 — `account` is a LIVE-TRACKING field, not the account at death (observed mutating)

Pane 127, same `session_id`, two reads 4 minutes apart:

```
census1.json @20:53Z : ['127', 98656, '11569d45-8a26-4bf0-a568-51efd70eff63', ..., 'claude-tertiary']
cat 127.json @20:57Z : {"pid":41980, "session_id":"11569d45-...", "account":"claude-secondary",
                        "lstart":"Sat Sep 19 20:57:00 2026"}
```

Same sid, new pid, new account: a transplant off the capped account, and the row followed it.
So `row.account` answers "where is it NOW", never "which account capped it". Marker-vs-row account
disagreement therefore is NOT registry error:

```
AGREE    pane=111 row=claude-tertiary(next3)  markers=['next3','next4']   09e64dcb   <- capped on BOTH
DISAGREE pane=121 row=claude-secondary(next2) markers=['next3']           65186f1f   <- already moved
DISAGREE pane=127 row=claude-secondary(next2) markers=['next3']           11569d45
DISAGREE pane=112 row=claude-secondary(next2) markers=['next4']           d02d8feb
DISAGREE pane=117 row=claude-secondary(next2) markers=['next4']           cb227486
agree=7 disagree=4 no_row=3
```

Name mapping is from the SSOT and is exact — `~/.claude/accounts.json`:
`next|~/.claude-next`, `next2|~/.claude-secondary`, `next3|~/.claude-tertiary`,
`next4|~/.claude-quaternary`. The registry writes the config-dir basename
(`session-register.sh:158  acct=$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')`);
the marker writes the launcher name resolved through that same SSOT
(`hooks/stop-failure-marker.sh:82-86`). Same input, two spellings — a consumer MUST normalise.

## R8 — the registry is a moving target inside one measurement window

Row count read at four instants across ~12 min: **32 → 33 → 32 → 31**. During the run:
- `~/.claude/cc-registry/124.json` went from present (sid 26cd14be) to **absent**, while kitty
  window 124 still existed;
- `~/.claude-tertiary/projects/.../26cd14be-....jsonl` vanished mid-`glob` (FileNotFoundError in
  `getmtime`) and reappeared as `26cd14be-....jsonl.handed-off` beside a `.HANDOFF.json`;
- pane 127's pid read alive at 20:53 and dead at 20:57.

Consequence for any detector: the census must be cheap enough to re-run per query (32 ms is), and
must `try/except FileNotFoundError` every stat — a transplant renames files under the scan.

## R9 — two instrument traps found while measuring (both fail silently, both look clean)

- **`lsof` cannot join pid→transcript.** `lsof -p <14 pids> -Fn | grep '\.jsonl$'` returns **zero**
  file rows in 0.67 s — Claude Code appends and closes. Any design that plans to resolve a live
  session's transcript by open-fd is dead on arrival; go through the registry sid or the filename.
- **mtime is not last-activity.** 98f02458's mtime is `2026-09-19T20:41:52Z` while its last content
  record is `19:57:42.975Z` — a 44-minute gap, because the harness rewrites the `last-prompt` /
  `mode` / `atis-latch` header block in place. Ranking or filtering candidates by mtime mis-orders
  them; read the tail's timestamp.
