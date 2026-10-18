# A3: SessionStart dispatcher architecture (`hooks/session-start-dispatch.sh`)

Axis A3 of the 9-axis startup-hooks study, written 2026-10-18 (CDT). This is read-only research. No
hook was executed. The only things run were transcript/IDL analysis, read-only replicas of one
directory scan, `jq`/`bash` timing probes, and `rg` over the Claude Code 2.1.293 binary.

Tags: **[M]** measured (the command is given) · **[E]** estimated (the method is given) ·
**[S]** static reading (file:line).

---

## 0. Headline

1. **One child causes the 9 s kills, and it is `config-mirror-assert.sh` on three of the four accounts.**
   On `.claude-secondary`, `-tertiary` and `-quaternary` it runs `_cc_sync_memory_mirror`, a zsh
   loop over the union of about 18,900 project slugs. A read-only replica of that loop alone
   took **8.8 s and 7.6 s** at load ~470 [M]. The dispatcher's duration histogram has a pile at
   **9.0 to 10.5 s (n=88)**. That is the 9 s bound plus 0.5 s median overhead [M]. On `.claude-next`,
   where the loop is skipped, 186 of 187 runs finish under 9 s [M]. Each kill also silently drops
   the four alarm classes this child owns: mirror forks, settings parity, hook-surface drift and
   agent-budget flags.
2. **The brief's premise "≥9 s ⇒ a child was killed" is only partly right, and the kill it does
   detect is invisible in transcripts.** The always-printing children (MCP, Plans, Tasks, Frontier,
   accounts-board) are present in 100 of 101 runs of 9 s or more [M]. The child that dies
   prints nothing when healthy, so its death leaves no trace anywhere. Only a per-child ledger can
   see it. Today none exists.
3. **The harness throws away all partial stdout when it cancels a hook, and its timer runs up to
   about 17 s late under load.** In 2.1.293 the `if(Jo.aborted){… hook_cancelled …}` branch yields no
   stdout [S, binary]. In the same 2 days, `mailbox-drain.sh` (timeout 5 s) *succeeded* at 13,184 ms
   and `dod-persist.sh` (5 s) was cancelled at 21,913 ms [M]. So no dispatcher deadline can fully
   protect output from a starved harness. Two more things are needed: a registration timeout set
   far above the dispatcher's own deadline (settings.json, class c10), and a durable outbox that a
   later hook re-renders when a cancel happens.
4. **`recycle-failed-inject.sh` can still lose a recovery packet.** It stamps `injected_at` right
   after writing to the dispatcher's temp file (`hooks/recycle-failed-inject.sh:52-59`). If the
   dispatcher is then harness-cancelled (6 of 410 runs, [M]), the packet is marked delivered while
   nothing reached the model. This is the repo's own lesson, "a reader that cannot prove delivery
   must not consume".
5. **The 9,500-character cap has never fired.** The largest merged context was 677 chars over 404
   runs [M]. The jq merge costs about 10 ms even at load ~470 [M]. A pure-bash merge would be a
   latency *trap* on `/bin/bash` 3.2. Fair per-child cutting is therefore cheap insurance, not a
   live problem.

---

## 1. Method

| Step | What | Command / file |
|---|---|---|
| 1 | Read the dispatcher, its 2 bats files and all 10 children's output paths | `hooks/session-start-dispatch.sh:1-93`, `tests/session-start-dispatch.bats`, `tests/migration-0056-session-start-dispatch.bats` |
| 2 | Per-run census with child signatures parsed from the dispatcher's recorded stdout | `python3 -I docs/research/startup-hooks-2026-10-18/a3_dispatch_census.py /tmp/startup-hooks-census-files.txt --rows /tmp/a3-dispatch-rows.tsv` |
| 3 | Time one child (session-index-start) from outside, using its EXIT-trap IDL row | `python3 -I docs/research/startup-hooks-2026-10-18/a3_child_timing.py` |
| 4 | Split the census by account (transcript path) and by which account the mirror warning names | jq loop → `/tmp/a3-acct.tsv` (§2.4) |
| 5 | Read-only replica of the memory-mirror scan | `zsh -fc` glob + `zstat -L` loop, no writes (§2.5) |
| 6 | Harness semantics: what happens to stdout on a timeout, the systemMessage threshold | `rg -a -o` over `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (2.1.293) |
| 7 | jq merge and bash startup cost at the current load | `/usr/bin/time -p jq -nc --rawfile …` ×5, `/usr/bin/time -p /bin/bash -c :` ×3 |

Known bias, from the brief: `hook_success` carries `durationMs` only when the hook prints. The
dispatcher prints on every run (the board alone guarantees it on non-compact starts), so the bias
does not apply to dispatcher rows. It does apply to the per-child inference: a child that prints
nothing when healthy is invisible. §2.3 works around that.

---

## 2. Measurements

### 2.1 Dispatcher duration (410 records in the brief's 411 main transcripts) [M: a3_dispatch_census.py]

```
dispatcher records: 410  success-with-ms: 404  cancelled: 6
success p50 5728  p75 8990  p90 9692  p95 10040  p99 10948  max 15603 ms
>=9000ms: 101  >=10000: 22  >=11000: 3  >=12000: 1
cancelled durations: 12261 12352 13544 15622 15872 21723 ms
by source: startup 382, resume 27, clear 1
```
These match the brief's p50 of 5.8 s. The brief's p99 of 13.5 s includes the cancels. One
**success at 15,603 ms against a 12,000 ms timeout** shows that the harness accepted output 3.6 s
after its own deadline. The kill timer runs late in both directions.

### 2.2 Child presence by duration band (success rows) [M: same script]

```
child                   <8s        8-9s      >=9s
session-start(MCP)      284/284    19/19     100/101
setup-plan-symlinks     284/284    19/19     101/101
setup-task-symlinks     284/284    19/19     101/101
frontier-status         284/284    19/19     101/101
accounts-board          284/284    19/19     101/101
session-index-start     0/284      0/19      0/101     (its filter suppresses the line)
activation-watch        0/284      0/19      0/101     (silent when healthy)
escalation-watch        4/284      0/19      3/101
config-mirror-assert    190/284    3/19      2/101     (warning-only)
recycle-failed-inject   0/284      0/19      0/101
merged ctx chars: p50 617 p90 643 max 677   cap hits (>=9500): 0
systemMessage chars: p50 2295 p90 2474 max 2854
```
**Every always-printer survives the slow runs.** The slow child must be one that is silent when
healthy.

### 2.3 Which child: the mirror warning against the 9 s pile [M]

Mirror-warning runs compared with the rest. Rows from `/tmp/a3-ts.tsv`, built with jq over the file list:

```
mirror=true   n=195  p10 1541  p50 2988  p90 6366  max 10853 ms
mirror=false  n=211  p10 5022  p50 8620  p90 9977  max 15603 ms
mirror=false histogram (whole seconds): 4:18 5:26 6:25 7:24 8:16 9:78 10:18 11:2 15:1
mirror=true  histogram (whole seconds): 0:2 1:49 2:48 3:40 4:24 5:8 6:8 7:11 8:3 9:1 10:1
```
Hour by hour the two are almost mutually exclusive. 2026-10-18T00 to 03Z: 41 runs, 41 mirror,
0 at 9 s or more. 2026-10-17T17Z: 13 runs, all 9 s or more, 0 mirror.

session-index-start is not the culprit [M: a3_child_timing.py, 366 runs joined]. Its exit offset
is p50 1.0 s and p90 4.8 s even in the slow runs, and only 4 of 90 slow runs had it near the bound.
For the 9.0 to 10.5 s pile, (dispatcher − 9000) is p50 498 ms and p90 977 ms. That is the
signature of the watchdog firing at 9 s plus the cost of reaping, merging and harness bookkeeping.

### 2.4 By account [M: jq loop → /tmp/a3-acct.tsv; ~/.claude-next/projects is a symlink to ~/.claude/projects]

```
transcript dir       mirror account named      <9s   >=9s
.claude (+ next)     .claude-next              186    1
.claude (+ next)     -                           3    2
.claude-quaternary   - / own / others           42   45
.claude-secondary    - / own                    45   41
.claude-tertiary     -                          29   12
```
`.claude-next` is fast and carries the warning (it has three forks). The three accounts with real
`projects/` dirs are slow and mostly silent: **97 of 213 runs (46%) at 9 s or more** [M].
`lib/config-mirror.zsh:298` returns early unless the account's isolate set lists `projects`
(`:45-48`). Only secondary, tertiary and quaternary list it [S].

### 2.5 The memory-mirror loop, replicated read-only [M]

`_cc_sync_memory_mirror` (`lib/config-mirror.zsh:293-378`) builds the union of
`~/.claude/projects/*(/)` and `$dst/projects/*(/)`. Then, for each slug, it does an lstat, a
`zstat +link` when the entry is a link, and `-d` tests. Project-dir counts [M: `ls … | wc -l`]:
18,228 / 18,197 / 18,148 / 18,172. The replica below runs the same glob and the same stat
calls, with no writes:

```
zsh -fc 'zmodload -F zsh/stat b:zstat; typeset -A s; for sp in ~/.claude/projects/*(N/) $D/projects/*(N/); do s[${sp:t}]=1; done; for slug in ${(k)s}; do …[[ -L ]] zstat… [[ -d ]] [[ -d ]]; done'
quaternary: slugs=18898  8.820 s wall (1.29 user 1.80 sys)
secondary:  slugs=18935  7.642 s wall (1.27 user 1.30 sys)      load average ~470-500
```
After that loop the child still runs: the config mirror over the ~1,288-entry `~/.claude`, a
`python3 cc-settings-parity`, two jq reads, `cc-agent-budget-flags` and a `python3` JSON encoder
(`hooks/config-mirror-assert.sh:17,77-79,85-95,99-102,110`). It cannot finish inside 9 s at this
load. Prior work measured this child at 224 ms on 2026-08-16 (`docs/research/startup-2026-08-16/COLD_START_100P.md:228`, which ruled it
"deferrable with zero semantic loss"). `sessionstart-readout-2026-10-06/README.md:296` lists its
account-dir path as unmeasured. This section fills that gap.

### 2.6 The 6 dispatcher cancels: harness starvation, not dispatcher logic [M]

SessionStart hook rows in the 6 sessions, from a jq listing per transcript:

| session | dispatcher | same-start siblings |
|---|---|---|
| e52f1f63 | cancel 12,352 | dod-persist cancel 9,095 (5 s) · mailbox-drain cancel 9,090 (5 s) |
| 5759497b (incident) | cancel 13,544 | dod-persist cancel 8,323 · mailbox-drain cancel 10,051 |
| dbc1098e | cancel 12,261 | mailbox-drain ok 4,568 · dod-persist ok 4,924 |
| 54b18e51 | cancel 15,872 | desk-brief cancel 13,368 · dod-persist 14,413 · mailbox-drain 14,413 |
| a86d22e3 | cancel 15,622 | dod-persist 9,425 · mailbox-drain 11,635 |
| 87e54489 | cancel 21,723 | **mailbox-drain SUCCESS 13,184 (5 s timeout)** · dod-persist cancel 21,913 |

In 5 of 6 sessions the 5 s hooks were also cancelled, and their cancels landed 3 to 17 s after
their deadlines. 87e54489 shows the harness processing a hook's *completion* 8 s after that
hook's timer should have fired. The 9 s child bound cannot explain a 21.7 s dispatcher run. Its
own processes were starved too: a `sleep 9` wake, `wait` and jq all need CPU. **Implication:** keep
the internal deadline. But protect the operator's output with an outbox the harness cannot cancel
(§4.6), and raise the registration timeout (§4.7).

### 2.7 Harness facts from the 2.1.293 binary [S: `rg -a -o` over claude.exe]

* Command-hook cancel path: `if(Jo.aborted){t(\`Hook ${Ye} … timed out after ${ii}ms\`) … yield{message:rn({type:"hook_cancelled",hookName:Ye,…,durationMs:ar,timedOut:!h?.aborted,timeoutMs:ii})…}`.
  **No stdout is carried**, even though `Jo.stdout` holds whatever was printed. So "print early,
  partially" is useless: only a completed exit counts.
* Hook output persistence: `async function mae(e,n,r,{threshold:s=ihs,…})` with `ihs=1e4`.
  A hook `systemMessage` over 10,000 chars is persisted to a file and replaced by a preview. The
  dispatcher already caps context at 9,500 but **does not cap the merged systemMessage**. The board
  (max 2,854) plus a long activation-watch listing plus mirror warnings could cross 10,000 and
  replace the board with a preview, with no warning.

### 2.8 Merge and startup cost [M]

`/usr/bin/time -p jq -nc --rawfile a /tmp/claude-accounts-board.txt --rawfile b hooks/session-start.sh '[$a,$b]|map(length)'`
×5 gave real 0.00 to 0.01 s at load ~470. `/bin/bash -c :` ×3 gave 0.00 to 0.03 s. `/bin/bash` is
3.2.57 [M: `--version`]. These probes ran at my session's priority. Hook processes inherit claude's
priority, which may be lower, so treat 10 ms as a floor [E].

### 2.9 Dispatcher token share [M: jq over the file list, average chars per context line by prefix]

`Frontier:` 278 · `Plans:` 184 · `Tasks:` 95 · `MCP:` 70, about 627 chars, ≈157 tokens [E: chars/4].
That is ~16% of the ~3,861-char SessionStart context average from the brief. The rest comes from
desk-brief, dod-persist and mailbox-drain (other axes). The board's 2.3 KB goes through
`systemMessage` at 0 model tokens.

---

## 3. Findings (by goal)

| ID | Goal | Finding | Evidence |
|---|---|---|---|
| F1 | latency + fault | config-mirror-assert's memory-mirror loop takes ≥7.6 s by itself on 3 accounts. It is killed at 9 s on 46% of their starts, and its alarms are dropped silently | §2.3-2.5 |
| F2 | fault | A killed child leaves **no record at all**: no ledger, no stderr (`:33` `exec 2>/dev/null`), no notice (`:65` kills, `:79-91` merge whatever exists) | [S] |
| F3 | fault | Four more silent exits: mktemp failure (`:46 \|\| exit 0`), no executable children (`:59`), no jq (`:70`), jq failure (`:91 \|\| OUT=""`). Each one loses the board and every notice with no trace | [S] |
| F4 | fault | The harness drops all stdout on cancel, and its timer lags by up to ~17 s. 6 of 410 dispatcher runs were cancelled, and none of those runs leaves a trace the operator can see | §2.6, §2.7 |
| F5 | fault | recycle-failed-inject stamps `injected_at` once its write to the dispatcher's temp file succeeds (`:52-59`), so a harness cancel loses the packet permanently | [S], §2.1 |
| F6 | fault | The context cap cuts mid-text from the END (`:88 $c[:$cap]`) with no notice. It has never fired yet (max 677) | §2.2 |
| F7 | fault | The merged systemMessage is uncapped. Above 10,000 chars the harness swaps it for a file preview | §2.7 |
| F8 | latency | The bound starts after the spawn loop (`:65`), not at process start. Bash start-up lag and spawn time under load are outside it, so the dispatcher's real deadline floats | [S], §2.3 pile overhead p90 977 ms |
| F9 | latency | Killing children at the bound also kills their **side effects**: half-run mirror heals, symlink setup, the session-index stub. Letting them finish in the background costs nothing at turn 1 | [S] `:61-65` |
| F10 | tokens | The dispatcher's design adds 0 tokens. Its context is ≈157 tokens [E] of child content, owned by the children (other axes) | §2.9 |

---

## 4. The spec: dispatcher v2

The design keeps the shape of the current file: one process, parallel children, one jq merge, one
print. It changes five things: when it prints, what it remembers, what it says on a drop, how it
cuts, and what it lets survive.

### 4.1 Emit-by-deadline (answers question a)

Constants, as env seams next to `:41-44`:

```
CC_SSD_EMIT_S=7     # wall deadline from PROCESS START (not from spawn). Print by then whatever finished.
CC_SSD_LATE_S=60    # late children keep running, detached, until this; then their group gets TERM, then KILL 2 s later
CC_SSD_CAP=9500     # context cap (unchanged)
CC_SSD_SMCAP=9000   # NEW: systemMessage cap, under the harness's 10,000 preview threshold
CC_SSD_LEDGER=~/.claude/logs/session-start-dispatch.jsonl
CC_SSD_SPOOL=~/.claude/state/ssd     # durable work dir (replaces $TMPDIR) so late output and the outbox survive the exit
```

Why 7 s. The registration is 12 s today. The p90 post-deadline overhead is ~1.0 s [M §2.3]. The
harness's late-processing lag reaches several seconds [M §2.6]. 7 s leaves ≈4 s of margin at 12 s,
and ≈12 s if the timeout is raised to 20 s (§4.7). With F1 fixed, the healthy distribution looks
like `.claude-next`'s: p50 3.0 s, p90 6.4 s [M §2.3, mirror=true runs]. So 7 s cuts almost nobody
[E]. Making the deadline relative to process start closes F8. One `ps -o etime= -p $$` read at the
top costs one fork, and its whole seconds are subtracted from the budget.

Mechanism (bash 3.2-safe, no `wait -n`, no fractional `read -t`). The watchdog sends `SIGUSR1` to
the dispatcher at the deadline. Bash documents that a trapped signal makes a blocking `wait` return
at once with a status above 128. POSIX requires this, and bash 3.2 behaves the same way. Bats test
T13 must prove it on `/bin/bash` explicitly.

```bash
# (replaces :46-68)
lag=$(ps -o etime= -p $$ 2>/dev/null); lag=${lag##*:}; lag=${lag#0}; case $lag in ''|*[!0-9]*) lag=0;; esac
mkdir -p "$SPOOL" 2>/dev/null
T="$(mktemp -d "$SPOOL/ssd.XXXXXX" 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/ssd.XXXXXX" 2>/dev/null)" \
  || loud "could not create a work dir, so all 10 startup hooks were SKIPPED (board, notices, Plans/Tasks/MCP lines). Check: df -h ~ ; ls -ld $SPOOL"
cleanup() { [ -e "$T/late" ] || rm -rf "$T"; }      # late ⇒ the collector owns $T
trap cleanup EXIT
trap 'term_now' TERM                                 # the harness kills at timeout: still leave a ledger row + outbox (§4.6)
: > "$T/t0"                                          # mtime = t0, read back with one stat (§4.2)
if [ -e /dev/fd/0 ]; then cat > "$T/payload" 2>/dev/null || :; else : > "$T/payload"; fi

i=0; map=""
for c in $CHILDREN; do
  i=$((i+1)); n=$(printf %02d "$i")
  if [ ! -x "$DIR/$c" ]; then printf '%s\t%s\tabsent\t-\n' "$n" "$c" >> "$T/status"; continue; fi
  # Wrapper: the rc file's mtime is the child's end time. All three fds leave the harness pipe:
  # a late child must never hold the dispatcher's stdout open.
  ( "$DIR/$c" < "$T/payload" > "$T/o$n" 2> "$T/e$n"; echo $? > "$T/r$n" ) </dev/null >/dev/null 2>&1 &
  map="$map $n:$!:$c"
done
[ -n "$map" ] || loud "none of the 10 startup hooks is installed/executable in $DIR. Re-run: bash ~/Development/claude-infrastructure/install.sh"

DEADLINE=0; trap 'DEADLINE=1' USR1
budget=$(( EMIT - lag )); [ "$budget" -lt 2 ] && budget=2
watchdog "$budget" &      # see below; stdout/stderr /dev/null
wd=$!
for e in $map; do p=${e#*:}; p=${p%%:*}; [ "$DEADLINE" = 1 ] && break; wait "$p" 2>/dev/null; done
late=""; for e in $map; do n=${e%%:*}; [ -e "$T/r$n" ] || late="$late $e"; done
if [ -z "$late" ]; then kill -TERM -- "-$wd" 2>/dev/null; else : > "$T/late"; fi   # hand $T to the collector
```

Watchdog / late collector, a function run in the background. It inherits `$T` and `$map`:

```bash
watchdog() {  # <budget-s>
  sleep "$1"; kill -USR1 $$ 2>/dev/null                  # phase 1: tell the parent to emit now
  # phase 2 (only matters if the parent marked "$T/late"): let late children finish, up to LATE_S
  local t=$1; while [ "$t" -lt "$LATE" ]; do
    all=1; for e in $map; do n=${e%%:*}; [ -e "$T/r$n" ] || all=0; done
    [ "$all" = 1 ] && break; sleep 2; t=$((t+2))
  done
  for e in $map; do n=${e%%:*}; p=${e#*:}; p=${p%%:*}
    [ -e "$T/r$n" ] && continue
    : > "$T/k$n"; kill -TERM -- "-$p" 2>/dev/null; sleep 2; kill -KILL -- "-$p" 2>/dev/null
  done
  [ -e "$T/late" ] || exit 0
  late_rows        # appends one ledger row per late child: st=late-ok|late-fail|killed, rc, ms (one stat), cc/sc chars
  late_outbox      # if a late child printed a systemMessage: write $SPOOL/late/<sid>.json for the Stop sentinel (§4.6)
  rm -rf "$T"
}
```

On the operator constraint: this *reduces* kills. A child that overruns is no longer killed at the
deadline. It keeps running in the background and is killed only at `LATE_S` = 60 s, a backstop for
real hangs. No live session work is touched.

### 4.2 Per-child timing and the kill ledger (answers question b)

**Where.** `~/.claude/logs/session-start-dispatch.jsonl`, append-only. One `>>` write per row from
the `printf` builtin; rows stay under ~1.5 KB [E: 10 children × ~110 B + header]. That matches
the create-mode contract of `scripts/rotate-autonomy-logs.sh:7-12`. **Rotation:** add the path to
`DEFAULT_TARGETS` at `scripts/rotate-autonomy-logs.sh:429-454`. Volume: ~205 runs a day × ~1.2 KB
≈ 250 KB a day [E: 410 runs / 2 days], well under any threshold.

**Timing without extra forks.** After the deadline, run one `stat -f '%Fm %N' "$T"/t0 "$T"/r*`.
APFS mtimes carry nanoseconds, so each child's `ms` is `mtime(rNN) − mtime(t0)`. jq's `now` minus
`mtime(t0)` gives the dispatcher's own total. That is one fork for all timing. Bash 3.2 has no
`EPOCHREALTIME`.

**Same jq, second output line.** The merge program (§4.5) prints line 1 = the hook JSON and line 2
= the ledger row. The shell splits on the first newline (`${OUT%%$'\n'*}` / `${OUT#*$'\n'}`), so
the ledger adds no fork.

**Row format (v1):**

```json
{"v":1,"ts":"2026-10-18T05:49:47Z","sid":"5759497b-…","src":"startup","cfg":".claude-quaternary",
 "pid":12345,"lag_s":1,"emit_s":7,"total_ms":7342,"printed":true,"ctx_out":627,"sm_out":2295,
 "kids":[{"c":"recycle-failed-inject.sh","st":"ok","rc":0,"ms":180,"cc":0,"sc":0},
         {"c":"config-mirror-assert.sh","st":"late","rc":null,"ms":null,"cc":null,"sc":null},
         {"c":"setup-plan-symlinks.sh","st":"ok","rc":0,"ms":2210,"cc":184,"sc":0,"cut":false}, …],
 "notices":["config-mirror-assert.sh late"]}
```
Late rows: `{"v":1,"kind":"late","sid":…,"pid":…,"c":"config-mirror-assert.sh","st":"late-ok|late-fail|killed","rc":0,"ms":14210,"cc":0,"sc":212}`.
Harness-TERM row (from `term_now`): `{"v":1,"kind":"harness-term","sid":…,"at_ms":…,"finished":[…],"pending":[…]}`.

`st` values: `ok` (rc 0, finished by the deadline) · `fail` (rc≠0 by the deadline: its stdout is
still merged, as the harness would for exit 0/1, and the rc is noted) · `late` · `absent` (not
executable) · `cut` (finished, but the cap dropped its context). This answers questions the
current census cannot, such as "which child, how long, on which account".

### 4.3 Loud drop notices (answers question c)

**Operator channel (systemMessage, 0 tokens): always, one line per affected child, placed FIRST**
so it is read before the board. Being first also moves the board's age line off line 1, where the
harness's ~31-column `SessionStart:startup says:` prefix wraps it
(`docs/lessons/sessionstart-systemmessage-accepts-sgr.md:32-36`). Format:

```
⚠ startup: config-mirror-assert.sh still running at 7s → mirror/parity/drift/budget checks NOT shown this start; result logs to ~/.claude/logs/session-start-dispatch.jsonl (late row) · re-check: zsh -fc 'source ~/.claude/lib/config-mirror.zsh; _cc_sync_account ~/.claude-quaternary'
⚠ startup: context cut by 9500 cap → dropped setup-task-symlinks.sh (95 chars), frontier-status.sh (278)
⚠ startup: merged banner 11,240 chars > 9000 → dropped escalation-watch.sh banner (2,100); run: bash ~/.claude/hooks/escalation-watch.sh --selftest
```

**Model channel (additionalContext): only when a MODEL-FACING child is late, cut or failed.**
Banner children never cost tokens. The table below sits in the jq program as data:

| child | channel | tier | model line on drop? | prescribed recovery (in the notice) |
|---|---|---|---|---|
| recycle-failed-inject.sh | ctx | 0 (never cut) | **yes**: `RECYCLE CHECK INCOMPLETE — if ~/.claude/autonomy/recycle-failed/<sid>.prompt.md exists, read it and act on it first.` | operator: `ls ~/.claude/autonomy/recycle-failed/<sid>.*` |
| session-start.sh | ctx (MCP claim, EFFORT_WARN) | 1 | yes: `MCP status line missing; do not assume MCP servers are connected.` | `tail ~/.claude/logs/sessions.log` |
| setup-plan-symlinks.sh | ctx + links | 2 | yes (≈15 tokens) | `find-plan.sh --list-open` |
| setup-task-symlinks.sh | ctx + links | 2 | yes (≈15 tokens) | `ls .claude-tasks/_current/` |
| session-index-start.sh | ctx (rare) + stub row | 3 | no (the line is filtered out 100% of the time [M §2.2]) | — |
| frontier-status.sh | ctx | 3 | no (a routing nudge; restated in CLAUDE.md) | — |
| accounts-board.sh | sm | — | no | `claude-accounts` |
| activation-watch.sh | sm | — | no | `bash ~/.claude/hooks/activation-watch.sh --queue` |
| escalation-watch.sh | sm | — | no | `tail ~/.claude/logs/autonomy-sweep*.log` |
| config-mirror-assert.sh | sm + mirror sync | — | no | the `_cc_sync_account` line above |

Token cost: 0 on a healthy start. On a drop, ≈15 to 40 tokens per model-facing child [E: chars/4
of the lines above]. Commands in the recovery column were taken from each child's own header. The
flags still have to be checked against each script before shipping. activation-watch documents
`--queue` as on-demand (`hooks/activation-watch.sh:19`). escalation-watch's `--selftest`
(`hooks/escalation-watch.sh:182`) is a fixture self-test, not a live health read, so its recovery
line should point at the sweep log instead.

**Static fail paths (F3)** use a `loud()` that needs no jq: `printf '{"systemMessage":"⚠ session-start-dispatch: %s"}\n' "$1"`.
Its text is fixed ASCII plus paths without quotes. Every `exit 0` at `:46`, `:59`, `:70` and
`:91` becomes a `loud` call.

### 4.4 Priority and cap (answers question d)

* The order stays the registration order, with recycle-failed-inject first, as designed (`:36-40`).
* **The cap becomes per-child, whole-or-nothing, in tier order** instead of `$c[:$cap]`
  (`:88`). Tier 0 gets the whole budget. If tier 0 alone is over the budget (a recovery
  packet > ~9.3 KB), it is truncated and a pointer line is added:
  `…[truncated N chars — read the full packet: <path>]`. The packet is a file, so nothing is lost.
  Lower tiers are then added whole while they fit. Each child that does not fit is named in the
  ⚠ cap notice and the ledger. This is fairer than proportional cutting, which would leave half a
  Plans line that reads as a complete statement.
* **New systemMessage cap 9,000** (F7). Notices are never dropped. Banners are dropped whole from
  the end of the order, and each drop is named.
* Today's numbers (max 677 ctx and 2,854 sm [M]) make both caps insurance. Cost: one jq `reduce`.

### 4.5 The jq merge: keep it, move it to a file (answers question e)

* **It is not a latency risk.** It is one fork, ~10 ms at load ~470 [M §2.8], against 10 children
  that each fork their own jq/python. In the slow pile, the whole post-bound overhead is p50
  ~0.5 s [M] and includes harness bookkeeping.
* **Pure bash is a trap here.** JSON-escaping the 2.3 KB ANSI-laden board in bash 3.2 means
  `${s//\\/\\\\}`-style global substitutions. The repo measured one such substitution at
  0.9 s for 2 KB and 6.5 s for 4 KB on 3.2 (`hooks/accounts-board.sh:164-166`). Parsing children's
  JSON in bash is fragile too. Rejected.
* Move the program to `hooks/lib/ssd-merge.jq` (`jq -nc -f`) so it can be unit-tested with
  fixture inputs and holds the child table (§4.3) as data. Inputs: `--rawfile oNN` per finished
  child, `--rawfile status`, `--rawfile times`, `--rawfile payload` (for sid/source),
  `--arg cfg "${CLAUDE_CONFIG_DIR##*/}"`, `--argjson cap/smcap/emit/lag`.
* Fallback: if jq is missing or fails, call `loud` (§4.3). The children have already run, so
  only the merged text is lost, and the notice says so.

### 4.6 The harness-cancel path: outbox plus Stop sentinel (closes F4 and F5)

1. **Outbox.** Before the final `printf`, write the exact line to `$SPOOL/outbox/<sid>.<src>.json`
   with `printed:true` in the ledger row. In `term_now` (TERM trap), write whatever has been merged
   so far, or a pending list, then exit.
2. **Sentinel in the Stop readout.** In `hooks/operator-readout.sh:1937-1961`, add a `_SS_LINE`
   next to `_DL_LINE`, using the exact pattern the ⏰ deadline line already uses: it rides every
   `_dl_msg` exit, it has an abstain override, and it keeps a per-session latch in `$STATE_DIR`.
   It scans the transcript from a latched byte offset with
   `tail -c +$off "$TP" | rg -F '"hook_cancelled"' | rg -F 'SessionStart'`. For each cancelled
   SessionStart hook it renders one line:
   `⚠ SessionStart: <command> was cancelled by Claude Code at <durationMs>ms (timeout <timeoutMs>) — its output reached neither you nor the model.`
   If the cancelled hook is the dispatcher, it also re-prints the outbox's systemMessage (the
   board and notices) and names the lost context lines. It also delivers `$SPOOL/late/<sid>.json`
   banners from late children (§4.1). This covers dod-persist, mailbox-drain and desk-brief
   cancels as well (other axes), with no settings edit.
3. **Recycle commit by proof.** Remove the stamp from `hooks/recycle-failed-inject.sh:54-59` and
   have it print the packet `token` in its context. The same Stop sentinel stamps `injected_at`
   only when the transcript holds a `hook_additional_context` row containing that token. With no
   proof, the next SessionStart injects it again. A duplicate is better than a drop, and that is
   the repo's own lesson (`docs/lessons/a-reader-that-cannot-prove-delivery-must-not-consume.md`).

### 4.7 Settings recommendation (operator-only, class c10)

Raise the dispatcher registration timeout **from 12 to 20 s**, through a new migration modelled
on `migrations/0056-session-start-dispatch.sh:64`, keeping the internal `EMIT_S=7`. This adds no
latency when healthy, because the dispatcher exits at its own deadline. It only stops a starved
harness from cancelling output that was already printed. Worst case, the dispatcher wedges past
its own watchdog and startup waits 20 s instead of 12 s. The TERM trap and `LATE_S` design make
that unlikely. The 0056 bats assertion (`tests/migration-0056-session-start-dispatch.bats:49`)
stays: it tests 0056's own output, and the new migration gets its own test.

### 4.8 Precompute in the background (answers question f)

* **config-mirror-assert.sh → precompute (the P0 fix).** At `:17`, detach the
  sync-plus-checks into a worker: `( worker </dev/null >/dev/null 2>&1 & )`, throttled by a
  per-account stamp (e.g. 600 s, like `setup-task-symlinks.sh:166-180`). The worker writes
  `~/.claude/state/config-mirror/<acct>.msg` (warning text, or empty) atomically. The SessionStart
  child only `cat`s the last result and labels its age with accounts-board's staleness bands
  (`hooks/accounts-board.sh:33-46`). Its own header says the work "fixes the NEXT session, not the
  running one" (`:5-6`), so nothing is lost. Expected effect: the child goes from ≥9 s (killed) to
  ~10 to 50 ms [E: one cat plus one stat, like accounts-board]. On 3 of 4 accounts the dispatcher
  moves toward next's p50 3.0 s and p90 6.4 s [E from §2.3]. The 4 alarm classes are shown again
  instead of dying at 9 s.
* **Make the memory-mirror walk incremental** (`lib/config-mirror.zsh:299-302`). Skip the
  18.9 k-slug loop when the mtimes of both `projects/` dirs are unchanged since the last full
  pass, using a stamp per destination. This is the S5 idea from
  `COLD_START_100P.md:500-509`, extended from the config walk to the memory walk. It also speeds up
  the zsh launcher, if `~/.zshrc` calls `_cc_sync_account` synchronously (it is cited at
  `COLD_START_100P.md:502` as `~/.zshrc:479`, a file outside the repo that I did not read).
* Other children: setup-task-symlinks already detaches its store sweep. session-start.sh's MCP
  line is stale-while-revalidate already (COLD_START_100P.md:226). accounts-board reads a
  pre-rendered file. Without a ledger there is no evidence that any other child needs
  precompute. Re-check this after a week of ledger rows.

### 4.9 Split accounts-board into its own registration? Verdict: no, not now

| | keep inside (recommended) | own registration |
|---|---|---|
| Survives a dispatcher cancel | via outbox + Stop re-render (§4.6) | yes, unless its own hook is cancelled. In 5 of 6 cancel sessions the 5 s siblings were cancelled too (§2.6), so a 5 s board hook would likely have died with them |
| Cost | 0 | one more harness spawn, bash and jq per start, plus a settings edit (c10), plus a migration |
| Can it go async? | — | no. An async systemMessage goes to the model and is hidden from the terminal (`hooks/session-start-dispatch.sh:14-15`) |
| Fixes the root cause | F1 fix + emit deadline + 20 s timeout | no |

Conviction 60 that keeping it inside is right. Reconsider if the ledger shows dispatcher cancels
continuing after §4.1, §4.7 and §4.8.

---

## 5. Edit points

| File:line | Change |
|---|---|
| `hooks/session-start-dispatch.sh:17-21,29` | Rewrite the BOUNDS and FAIL-OPEN header: emit-by-deadline, late-continue, FAIL-LOUD |
| `:30,41-44` | Add env seams `CC_SSD_EMIT_S`, `CC_SSD_LATE_S`, `CC_SSD_SMCAP`, `CC_SSD_LEDGER`, `CC_SSD_SPOOL` |
| `:46-48` | Spool work dir, `loud` fallback, late-aware cleanup, TERM trap, t0 marker |
| `:52-59` | Wrapper with an rc file; `absent` status; loud if nothing is executable |
| `:61-68` | USR1 deadline watchdog plus late collector (§4.1) in place of kill-at-bound |
| `:70-74` | `loud` when jq is missing; add `status`/`times`/`payload` rawfiles |
| `:76-91` | Move to `hooks/lib/ssd-merge.jq`: tiers, whole-or-nothing cap, sm cap, notices, model lines, ledger line 2 |
| `:91-92` | `loud` on jq failure; ledger append, outbox write, then print |
| `hooks/config-mirror-assert.sh:17,103-111` | Detached throttled worker writes `<acct>.msg`; the hook cats it with age bands |
| `lib/config-mirror.zsh:299-302` | Gate the memory walk on an mtime stamp of both `projects/` dirs |
| `hooks/recycle-failed-inject.sh:49-59` | Print the token; remove the stamp (moved to the sentinel) |
| `hooks/operator-readout.sh:1937-1961` | `_SS_LINE` startup-cancel sentinel, outbox re-render, late banners, recycle commit-by-proof |
| `scripts/rotate-autonomy-logs.sh:429-454` | Add `$HOME/.claude/logs/session-start-dispatch.jsonl` |
| new `migrations/00NN-ssd-timeout-20.sh` + bats | Registration timeout 12 → 20 (settings, c10) |

---

## 6. Bats test plan (`tests/session-start-dispatch.bats`, plus a new `tests/ssd-merge-jq.bats`)

All tests are hermetic and follow the file's current `setup()`: fixture children in
`$BATS_TEST_TMPDIR/hooks`, `HOME` redirected, `CC_SSD_LEDGER` and `CC_SSD_SPOOL` under
`$BATS_TEST_TMPDIR`. Each runs under `/bin/bash` explicitly.

| # | Test | Asserts |
|---|---|---|
| T1 | existing 6 tests | still pass. "capped" (`:76-80`) is rewritten for whole-or-nothing semantics |
| T2 | deadline: `fast.sh` + `slow.sh` (sleep 30), `CC_SSD_EMIT_S=2` | exits in < 4 s; context = FAST; sm line 1 starts `⚠ startup: slow.sh still running at 2s` |
| T3 | late child finishes | `slow.sh` (sleep 4, touch marker, echo X) with EMIT 2, LATE 10: marker exists after ~4 s; ledger gains a `kind:late,st:late-ok,rc:0` row; spool dir removed afterwards |
| T4 | LATE cap kill | `hung.sh` (exec sleep 60) with LATE 4: pid gone after ~6 s; ledger `st:killed`; no orphan (`kill -0` fails) |
| T5 | no pipe hold | `bash ssd \| cat` returns within EMIT+2 s while a late child runs, so the late child does not hold stdout |
| T6 | per-child cap | tier-0 child 9,000 chars + 2 children of 400: tier 0 kept whole, both others dropped, both named in sm, ledger `st:cut` |
| T7 | tier-0 overflow | 12,000-char recycle fixture: context ≤ CAP and ends with `[truncated … read the full packet:` |
| T8 | sm cap | 3 banner children of 4,000: sm ≤ 9,000, last banner dropped and named, notices line present |
| T9 | no jq | `PATH` without jq: stdout is valid JSON (checked by a test-side python3), top-level systemMessage begins `⚠ session-start-dispatch:` |
| T10 | no work dir | `CC_SSD_SPOOL` and `TMPDIR` unwritable: loud static JSON, exit 0 |
| T11 | ledger shape and concurrency | 20 parallel dispatches → 20 parseable rows with the fields in §4.2; every child `ms` ≥ 0 |
| T12 | model-line policy | late `setup-task-symlinks.sh` fixture adds a model line to ctx; late `accounts-board.sh` fixture adds no ctx line (0 tokens) |
| T13 | USR1 interrupts wait on bash 3.2 | wall time of T2 under `/bin/bash` (3.2) < EMIT+2 |
| T14 | outbox | `$SPOOL/outbox/<sid>.startup.json` is byte-identical to stdout |
| T15 | TERM trap | send TERM to the dispatcher mid-run: a `kind:harness-term` ledger row exists, listing pending children |
| T16 | merge jq unit tests (`ssd-merge-jq.bats`) | channel split, plain text, invalid JSON as plain text, order, tiers, notice text, ledger line, all from fixture rawfiles |
| T17 | sentinel (`operator-readout.bats` addition) | fixture transcript with a SessionStart `hook_cancelled` for the dispatcher plus an outbox: one ⚠ line, board re-rendered, latch prevents a repeat |
| T18 | recycle commit-by-proof | child does not stamp; sentinel stamps only when the transcript holds the token |
| T19 | config-mirror precompute | the hook forks no zsh in the foreground (stub zsh records calls, as accounts-board.bats does for claude-accounts); prints the cached msg with an age label; stale/missing → one loud line |

---

## 7. Recommendations (ranked)

| # | Recommendation | Impact | Effort | Risk | settings.json? | Conviction |
|---|---|---|---|---|---|---|
| R1 | config-mirror-assert → background precompute plus cached read (§4.8) | Removes the 9 s pile on 3 of 4 accounts: dispatcher p50 ~8.6 s → ~3 s on those accounts [E: §2.3 mirror=false vs mirror=true]. The startup span saving is bounded by the next-slowest sync hook (5 s hooks). Re-shows 4 dropped alarm classes | S | Low: the work "fixes the NEXT session" by its own header. Warnings lag up to one throttle interval | no | 90 |
| R2 | Loud static fail paths plus per-child kill/late notice in sm (§4.3); the smallest diff that closes F2 and F3 | Closes 5 silent-drop paths; 0 tokens when healthy | S | Low | no | 90 |
| R3 | Durable per-child ledger through the same jq plus one stat; rotation target (§4.2) | Makes every child's ms/rc/state attributable; enables later audits | S-M | Low (append-only, ~250 KB/day [E]) | no | 85 |
| R4 | Emit-by-deadline: USR1, deadline from process start, late children continue to 60 s (§4.1) | Bounds dispatcher exit at ~EMIT+1 s p90 [E]; keeps side effects of slow children; fewer kills | M | Medium: background processes outlive the hook (fd hygiene covered by T5) | no | 75 |
| R5 | Registration timeout 12 → 20 s (§4.7) | Protects already-printed output from harness timer lag (6/410 cancels [M]); 0 ms typical | S | Low-medium: worst-case wedge waits 20 s | **yes (c10)** | 70 |
| R6 | Outbox plus Stop sentinel for SessionStart cancels, re-rendering the board and notices (§4.6) | Makes every harness cancel of any SessionStart hook loud and attributable, with recovery | M | Low: reuses the ⏰ line mechanism | no | 75 |
| R7 | recycle-failed-inject commit-by-proof (§4.6.3) | Closes permanent loss of a recovery order on a harness cancel | M | Low: worst case is a duplicate injection | no | 80 |
| R8 | Per-child whole-or-nothing ctx cap plus 9,000 sm cap with named drops (§4.4) | Insurance today (0 cap hits [M]); stops the 10 k preview swap of the board | S | Low | no | 70 |
| R9 | Keep the jq merge; move it to `hooks/lib/ssd-merge.jq` (§4.5) | Testability; avoids the bash 3.2 superlinear trap | S | Low | no | 80 |
| R10 | Memory-mirror mtime gate in `lib/config-mirror.zsh` (§4.8) | ~7.6 to 8.8 s CPU-wall per run [M replica] → ~0 when nothing changed; also the launcher path | M | Medium: a missed heal if the mtime does not move (backstopped by a periodic full pass) | no | 65 |
| R11 | Do NOT split accounts-board out now (§4.9) | — | — | — | (would be yes) | 60 |

---

## 8. Open questions

1. Which other children are slow on the fast accounts? `.claude-next` runs still reach p90 6.4 s
   [M]. Only the R3 ledger can attribute that.
2. Does Claude Code's SessionStart wait hold back the first model turn, or only the startup
   rendering? This decides how much of R1's saving reaches the operator. The startup span is the
   maximum over all sync hooks: dod-persist, desk-brief and mailbox-drain, each 5 s.
3. Does the harness kill the hook's process group or only the pid at timeout, and does it close
   our stdout before a late child could inherit it? T5 covers our side; the harness side was not
   traced.
4. Is `ps -o etime=` for `$$` the harness spawn time? That holds if the harness execs the command
   directly or through `sh -c` with exec optimization. If a wrapper shell stays as the parent, the
   lag is under-measured by the wrapper's startup.
5. Does `~/.zshrc:479` call `_cc_sync_account` synchronously at every `claude` launch on the three
   isolated accounts? If it does, the 7.6 to 8.8 s walk is also on the launcher path (beyond-startup).
   `~/.zshrc` is outside the repo and was not read.
6. Why is the memory walk so I/O-bound (35% CPU)? 18.9 k lstats at load ~470 suggests filesystem
   metadata contention. Pruning dead project slugs (18 k dirs per account) may be worth its own
   axis.
7. Do the `--queue`/`--selftest` recovery commands in §4.3 exist and run without side effects for
   every child? This must be checked per script before the notice texts ship.

---

## Artifacts

* `docs/research/startup-hooks-2026-10-18/a3_dispatch_census.py`: per-run child attribution (read-only).
* `docs/research/startup-hooks-2026-10-18/a3_child_timing.py`: session-index-start exit offset join, and the 9 s pile overhead.
* Intermediate tables (not committed): `/tmp/a3-dispatch-rows.tsv`, `/tmp/a3-ts.tsv`, `/tmp/a3-acct.tsv`.
