# P2-payload-paths — StopFailure payload keys measured against live truth
Measured 2026-09-19T20:5x-21:1xZ, read-only, box = this worktree. Corpus = every marker row on disk.

## R0 — corpus and field shape
```
$ cd ~/.claude/autonomy/stop-failure/ && for f in *.jsonl; do echo "$f lines=$(wc -l <$f)"; done
authentication_failed__.claude.jsonl  lines=5
rate_limit__next3.jsonl               lines=12
rate_limit__next4.jsonl               lines=14
$ cat ~/.claude/autonomy/stop-failure/*.jsonl | jq -r 'keys|join(",")' | sort | uniq -c
  31 account,config_dir,cwd,error,hook_event_name,last_assistant_message,session_id,transcript_path,ts
```
31 rows, one field-set, 0 parse failures. **19 distinct session_ids.**
NOTE the payload does NOT carry `pane`, `effort`, or `prompt_id` in ANY row on disk — the hook
declares effort/prompt_id optional (hooks/stop-failure-marker.sh:22-24) and jq-encodes only the
nine fields above (hooks/stop-failure-marker.sh:121-127). No pane id exists anywhere in a marker.

## R1 — session_id: 31/31 OK, but "?" is reachable by construction
```
$ python3 /tmp/p2cls.py  (classifier over all rows)
TOTAL ROWS: 31
15 ('SID-OK','TP-HANDEDOFF','CWD-LIVE')
13 ('SID-OK','TP-LIVE','CWD-LIVE')
 2 ('SID-OK','TP-LIVE','CWD-GONE')
 1 ('SID-OK','TP-HANDEDOFF','CWD-GONE')
```
No row carries `?`. But hooks/stop-failure-marker.sh:75 is
`SID="$(jqs '.session_id // .sessionId // "?"')"; [ -n "$SID" ] || SID="?"` — the sentinel is
written, not abstained on. Only `error` is a hard requirement (`:79 [ -n "$ERR" ] || _sf_abstain
"no-error-field"`). So a payload without a session_id yields an UNJOINABLE row, silently.
VERDICT: HOLDS on this corpus, structurally unguaranteed. A consumer must reject sid=="?".

## R2 — transcript_path: 16/31 rows (52%) point at a file that no longer exists
All 16 have a `.handed-off` sibling; 0 rows are GONE-without-sibling.
```
$ python3 /tmp/p2ho.py   (marker ts vs .handed-off mtime, all 16 non-live rows)
next3 98f02458 marker=2026-09-19T19:52:33Z ho_mtime=2026-09-19 20:53:31Z delta=-3658s
next4 09e64dcb marker=2026-09-19T17:11:29Z ho_mtime=2026-09-19 17:22:13Z delta= -644s
... (16 rows)
born_dead: 0   went_stale_later: 16
```
Every one went stale AFTER it was written. Shortest survival **644 s (10.7 min)**, longest 3658 s,
median ~2500 s (~42 min). **transcript_path is a snapshot with a ~10-minute worst-case shelf life.**

## R3 — the SAME session_id exists in TWO accounts (the transplant re-fire)
```
$ cat ~/.claude/autonomy/stop-failure/*.jsonl | jq -r 'select(.session_id=="09e64dcb-…")|[.ts,.account,.transcript_path]|@tsv'
2026-09-19T19:53:38Z  next3  /Users/chrisren/.claude-tertiary/projects/…/09e64dcb-….jsonl
2026-09-19T17:01:34Z  next4  /Users/chrisren/.claude-quaternary/projects/…/09e64dcb-….jsonl
2026-09-19T17:11:29Z  next4  /Users/chrisren/.claude-quaternary/projects/…/09e64dcb-….jsonl
$ ls -la ~/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/ | grep 09e64dcb
-rw-------  6962734 Sep 19 15:43 09e64dcb-….jsonl                 <- LIVE, growing
$ ls -la ~/.claude-quaternary/projects/-Users-chrisren-Development-claude-infrastructure/ | grep 09e64dcb
-rw-r--r--      331 Sep 19 12:22 09e64dcb-….HANDOFF.json
-rw-------  5424877 Sep 19 12:22 09e64dcb-….jsonl.handed-off      <- source carcass
```
A transplant PRESERVES the sid and moves it between config dirs. So session_id is globally unique
but **NOT account-scoped**, and the marker's `account` field is a claim about the moment of death.
Also visible: markers re-fire. 6 of 19 sids appear 2-4x (`e442434c` 4x, `28f07827` 4x), i.e. 31
rows describe 19 sessions — a naive `wc -l` overcounts the fleet by 63%.

## R4 — the marker's `account` is WRONG for 3 of the 11 resolvable sids (27%)
```
$ python3 /tmp/p2res.py
registry index: 32 rows in 1 ms ; distinct marker sids: 19
0874804f marker_acct=.claude  NO-REGISTRY-ROW      (x5 — all the auth_failed rows)
d02d8feb marker_acct=next4    reg_acct=next2 pane=112 pid_alive=False MOVED
cb227486 marker_acct=next4    reg_acct=next2 pane=117 pid_alive=False MOVED
65186f1f marker_acct=next3    reg_acct=next2 pane=121 pid_alive=True  MOVED
28f07827 marker_acct=next4    NO-REGISTRY-ROW
e442434c marker_acct=next4    NO-REGISTRY-ROW
98f02458 marker_acct=next3    NO-REGISTRY-ROW
09e64dcb marker_acct=next3    reg_acct=next3 pane=111 pid_alive=True  same
… resolved via registry: 11/19  unresolved: 8  account-mismatch: 3
```
`65186f1f` is the decision-bearing one: the marker files it under next3, it is ALIVE on next2, and
a census that groups by marker filename would queue it for recovery while it is working.

## R5 — the transplant signature is mechanically datable (registry.startedAt ≈ ho_mtime + 60 s)
```
$ python3 -c "…utcfromtimestamp(startedAt/1000)…"
pane 121 (65186f1f) startedAt 2026-09-19T20:48:39Z   ho_mtime 20:47:43Z  (+56 s)  marker 19:57:41Z
pane 112 (d02d8feb) startedAt 2026-09-19T17:20:49Z   ho_mtime 17:19:54Z  (+55 s)  marker 16:59:19Z
pane 117 (cb227486) startedAt 2026-09-19T17:55:02Z   ho_mtime 17:53:01Z  (+121 s) marker 17:07:16Z
```
All three registry rows are NEWER than their marker. That ordering IS the move detector, and it
needs no transcript read: `registry.startedAt > marker.ts` ⇒ the sid was re-registered after death
⇒ the marker's account/pane/transcript are all superseded.
Registry sid uniqueness verified: `jq … | awk '{c[$1]++} END{if(c[k]>1)…}'` printed nothing ⇒ no
sid maps to two panes, so sid→pane is a function.

## R6 — cwd is a DECAYING key: 1 GONE → 3 GONE in ~25 min with zero new rows
```
run 1 (~20:55Z): 15 TP-LIVE/CWD-LIVE · 15 TP-HANDEDOFF/CWD-LIVE · 1 TP-HANDEDOFF/CWD-GONE
run 2 (~21:15Z): 13 TP-LIVE/CWD-LIVE · 15 TP-HANDEDOFF/CWD-LIVE · 2 TP-LIVE/CWD-GONE · 1 TP-HO/CWD-GONE
TOTAL ROWS: 31 in BOTH runs (no new markers)
$ stat -f '%Sm %N' /Users/chrisren/Development/.worktrees
Sep 19 15:55:00 2026 /Users/chrisren/Development/.worktrees   <- a reap between the two runs
$ ls -d /Users/chrisren/Development/.worktrees/wt-cc-095358-75429 => No such file or directory
```
CWD-GONE rows: d02d8feb (wt-cc-095358-75429), fff83638 (wt-cc-142546-79030), 0e2567ee
(wt-cc-142549-10206) — all reaped worktrees. A recovery that `cd`s to a marker cwd fails here.

## R7 — the `.claude` phantom account: 5/31 rows are filed under a name no account owns
```
$ cat …/authentication_failed__.claude.jsonl | jq -r '[.ts,.account,.config_dir,.cwd]|@tsv'
2026-09-17T09:19:25Z  .claude  /Users/chrisren/.claude  /Users/chrisren/Development/reso-qa-runner
… 5 rows, one per day ~09:19Z, all reso-qa-runner
$ jq -r '.accounts[]?|[.name,.config_dir]|@tsv' ~/.claude/accounts.json
next  ~/.claude-next
next4 ~/.claude-quaternary
next3 ~/.claude-tertiary
next2 ~/.claude-secondary
```
`~/.claude` is NOT in the accounts SSOT, so hooks/stop-failure-marker.sh:88
(`[ -n "$ACCOUNT" ] || ACCOUNT="$(basename "$CFG")"`) names the cause file `__.claude`. The marker
FILENAME is the operator-visible fact (hook header, :9-15) — so a per-account census reads a fifth
account `.claude` that has no launcher, no quota row and no registry rows (5/5 NO-REGISTRY-ROW,
R4). Their transcripts are all LIVE (5/5) because they are headless cron runs that were never
transplanted. VERDICT: these are real deaths, correctly captured, mis-grouped.

## R8 — `locks/<sid>.lock` does not exist as a surface (REFUTED as a third key)
```
$ find ~/.claude ~/.claude-next ~/.claude-tertiary -maxdepth 3 -name '*.lock'
/Users/chrisren/.claude/session-index.lock
/Users/chrisren/.claude/ide/53785.lock …
$ cat ~/.claude/ide/53785.lock
{"pid":602,"workspaceFolders":["…"],"ideName":"Cursor","transport":"ws","authToken":"…"}
$ ls ~/.claude*/ide/*.lock | wc -l
8
```
`ide/*.lock` are PID-keyed Cursor WS locks carrying NO session_id; 8 files fleetwide against 19
sids. There is no lock surface that can re-resolve a marker.

## R9 — cost of the full re-resolution
```
$ for i in 1 2 3; do python3 /tmp/p2cost.py | tail -1; done
TOTAL: 1.9 ms  syscalls~121
TOTAL: 1.6 ms  syscalls~121
TOTAL: 1.4 ms  syscalls~121
  markers read (31 rows): ~0.3 ms · registry index (32): ~0.6 ms · stat+kill (19 sids): ~0.5 ms
```
Against `lr-fleet.sh --locate` = 35.5 s / 2,591 transcripts (lead's measurement today).
~20,000x, single process, zero transcript reads, zero forks.

## THE RE-RESOLUTION RULE (marker → live truth), derived from R1-R9
Input: all rows under `~/.claude/autonomy/stop-failure/*.jsonl` + `~/.claude/cc-registry/*.json`.

0. DROP rows with `session_id == "?"` or empty (R1) — unjoinable, count them as a named loss.
1. COLLAPSE to one row per sid, keeping MAX(ts) (R3: 31 rows → 19 sessions; never `wc -l`).
2. JOIN sid → registry (sid→pane is a function, R5). Three outcomes:
   a. **no registry row** (8/19) ⇒ UNADDRESSABLE — headless/`-p`/pre-registry. Report by sid+cwd,
      never queue for in-place recovery.
   b. **registry.startedAt > marker.ts** (3/19) ⇒ **MOVED**. Live account = registry.account
      (normalise launcher→SSOT: claude-secondary→next2 …), live pane = registry filename.
      The marker's `account`, `config_dir` and `transcript_path` are ALL superseded. If pid is
      alive ⇒ NOT a recovery candidate at all (R4, 65186f1f).
   c. **registry.startedAt <= marker.ts** (8/19) ⇒ marker account still true; pane = registry file.
3. LIVENESS: `kill -0 registry.pid`. Alive ⇒ running (or phantom-mid-turn, see the beat caveat);
   dead ⇒ the pane is a candidate.
4. TRANSCRIPT arm, for the salvage path only: `exists(tp)` ⇒ addressable · `exists(tp+".handed-off")`
   ⇒ already transplanted out, the marker names a carcass (16/31) · neither ⇒ UNKNOWN-GONE (0/31,
   reserve the class, do not assume it cannot happen).
5. CWD arm: `isdir(cwd)` at RESOLVE time, never at marker time (R6). GONE ⇒ the worktree was reaped;
   any recovery must re-provision or pick the registry row's `cwd` instead.
6. GROUPING for the operator: group by the RESOLVED account from step 2, NOT by marker filename
   (27% misgrouping, R4), and render `.claude` as a distinct non-account surface (R7).

Cost: ~1.5 ms, ~121 syscalls, no transcript reads, no subprocess.
Staleness bound: the marker's own fields are trustworthy for ~10 min minimum (R2 worst case), so a
census that re-resolves at READ time is correct at any age; one that trusts the row is not.

## Dependencies noted, not designed (recovery chain is out of scope for this wave)
- Step 3's liveness is necessary but NOT sufficient: `cc_sp_active`
  (scripts/lib/spawn-presence.sh:298, lead's measurement) counts a limit-dead pane as mid-turn
  because Stop never fires on a limit turn, so a live pid does not mean a live turn.
- The `.claude` surface (R7) has no pane and no launcher; recovering it is a different mechanism.
