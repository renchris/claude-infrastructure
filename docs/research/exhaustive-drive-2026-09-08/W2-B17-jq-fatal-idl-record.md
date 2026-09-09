# W2-B17 — the jq-fatal IDL record: producer, cause, and the 12.33 % every jq census drops

**ONE jq-fatal record exists across the live IDL and all 8 gz archives (2 malformed lines from 1
spliced write), and its producer is LIVE: `scripts/autonomy-sweep.sh:1400` emits a 6,679-byte
`backlog-health` record through `log_idl` (`scripts/autonomy-sweep.sh:193-207`), and ALL 72 of its
emissions over the 11-day window exceed the 4,096-byte atomic-append boundary. Cause class =
INTERLEAVED CONCURRENT APPEND, none of the five the brief proposed. A jq census over that population
silently drops 118,666 of 962,681 records — 12.33 % overall, 24.3 % of `hook` records. VERDICT:
CROSSES 90 (conviction 96) for the one-line producer fix PLUS the tolerant-reader rule.**

## 1. The record

| | |
|---|---|
| Location | `~/.claude/autonomy/idl.jsonl.20260907T055617Z.gz`, lines **107,854** and **107,856** |
| Census position | line **844,016** — exactly the position A07-sk2 M1 reported |
| Malformed lines | 2 (one head fragment of **4,242** B, one orphaned tail of **2,583** B) |
| The record they came from | **6,679** B, 37 fields, reassembles to valid JSON when the splice is removed |
| `tool` / `disposition` | `autonomy-sweep` / `backlog-health` (this store has no `kind`/`event`/`by` on this family; the `kind`-shaped rows are the `actor` family — §4) |
| jq's message | `jq: parse error: Invalid literal at line 844016, column 4101`, rc **5** |

First 300 bytes of the head fragment:

```
{"ts":"2026-09-07T05:08:35Z","tool":"autonomy-sweep","disposition":"backlog-health","new_pages":2,
"new_alarms":0,"new_pushfailed":0,"open_decisions":0,"fired_defaults":0,"fired_nochange":0,
"new_handoff_alarms":1,"consolidation_trigger_rc":"124","ratchet_rc":"124","ratchet_filed":"n-a",
"drain_chain_r…
```

At byte offset **4,096** — not 4,095, not 4,100 — the record stops mid-string and a *different
process's complete record* begins:

```
…bound-exceeded = rc 124 and {"ts":"2026-09-07T05:08:37Z","hook":"waiting-recycle",
"sid":"4541ee04-…","disposition":"abstained","reason":"not-armed"}
```

Line 107,855 is a second intact `waiting-recycle` record (05:08:38Z). Line 107,856 is the sweep
record's remaining 2,583 bytes, orphaned. **The sweep's `write()` was split at the 4 KiB boundary and
two peer appends landed in the gap.**

## 2. Cause class — INTERLEAVED CONCURRENT APPEND (not escaping, truncation, control bytes, or UTF-8)

Both writers are correct in isolation. `hooks/lib/idl-log.sh` and `autonomy-sweep.sh:196-198` carry
the same load-bearing comment — *jq-encode EVERY field, one malformed line aborts the slurp* — and
both obey it. jq's encoding is not the defect. The defect is the **transport**:

1. The IDL is a single file appended by ~20 concurrent producers, each with `>> "$IDL"` (O_APPEND).
2. jq writes stdout through stdio, whose buffer is the target's `st_blksize` — **4,096** on this
   file (`stat -f %k ~/.claude/autonomy/idl.jsonl` → `4096`).
3. A record **longer than 4,096 bytes is therefore ≥ 2 `write()` syscalls**. O_APPEND makes each
   write atomic *individually*; it does not make the pair atomic. Any peer appending between them
   splices its record into the middle of ours.

Red-proof, run in the scratchpad (not committed — W3 should lift it as the fix's falsifier):

```bash
OUT=$(mktemp); BIG=$(python3 -c 'print("z"*6000)')
( for i in $(seq 1 4000); do jq -cn --arg i "$i" '{ts:"T",hook:"peer",n:$i}' >>"$OUT"; done ) & P=$!
for i in $(seq 1 300); do
  jq -cn --arg b "$BIG" '{ts:"T",tool:"autonomy-sweep",disposition:"backlog-health",note:$b}' >>"$OUT"
done; wait $P
python3 - "$OUT" <<'EOF'
import json,sys,re
bad=[]
for line in open(sys.argv[1],'rb'):
    try: json.loads(line.decode())
    except Exception:
        m=re.search(rb'\{"ts":"T","hook":"peer"',line); bad.append(m.start() if m else -1)
print("malformed:",len(bad),"splice offsets:",sorted(set(bad)))
EOF
```

- **Defect arm** (6,000-byte note): **14-16 malformed lines** across runs, splice offsets
  `[-1, 4096]` — every *head* fragment is cut at exactly 4,096 (the `-1` entries are the orphaned
  tails, which carry no peer prefix to locate). A constant 4,096 is what makes this the stdio-buffer
  mechanism and not a generic race.
- **Control arm**, same concurrency, note shortened to 3,000 B so the record is ≤ 4,096:
  **0 malformed lines** over 300 emissions. The size threshold is sufficient, not merely correlated.

## 3. The producer, and it is still live

**`scripts/autonomy-sweep.sh:1400`** — `log_idl backlog-health "$(jq -cn …)"`, whose writer is
`log_idl` at **`scripts/autonomy-sweep.sh:193-207`** (a plain `jq … >> "$IDL"`; the identical shape
lives in `hooks/lib/idl-log.sh:73-80` for every hook producer).

The record is oversized for exactly one reason: a **5,763-byte constant `note:` literal**, byte-identical
on all 72 emissions. Strip it and the record is **845 bytes** — 4.8× under the boundary.

| Check | Reading |
|---|---|
| Deployed copy | `~/.claude/scripts/autonomy-sweep.sh` → symlink into the shared checkout; `diff` vs this worktree: **identical**. No fix has landed. |
| Emissions in the window | **72**, and **100 % of them exceed 4,096 B** (min intact 6,629, max 6,652) |
| Newest emission | **2026-09-07T21:10:56Z** (~30 h before this measurement) |
| Why none in the last 30 h | Not a code change. The sweep still ticks every 300 s (163 `autonomy-sweep` rows in the live file's 14 h), but `sweep_yield` (`:312-325`) self-bounds before §2b under the current box load — **20 `self-bound` rows** in that same window. §2b is reached intermittently, not retired. |
| Interleave rate | 1 of 72 (**1.4 %**) — a lottery every emission enters, not a one-off |
| Next-largest emitter | `autonomy-sweep/cloud-return` at **988 B** — 4.1× headroom, so this is genuinely a single-site fix today |

## 4. Population and denominator

Census reconstructed to match A07-sk2 M1 exactly: **`idl.jsonl` (first 54,256 lines — its length when
that axis ran) followed by the 8 `idl.jsonl.2*.gz` archives ascending**. That ordering puts the first
fatal line at **844,016** and yields **86,122** tolerant `hook` records — both of M1's figures land on
the nose, which is what pins the ordering.

```bash
cd ~/.claude/autonomy
{ head -54256 idl.jsonl; gzcat idl.jsonl.2*.gz; } > /tmp/census.jsonl
jq -r 'select(.hook)|.hook' /tmp/census.jsonl | wc -l   # 65159, rc 5, aborts at 844016
python3 - /tmp/census.jsonl <<'PY'
import json,sys,collections
n=0;fatal=None;b=collections.Counter();a=collections.Counter()
for line in open(sys.argv[1],'rb'):
    n+=1
    try: o=json.loads(line.decode())
    except Exception:
        if fatal is None: fatal=n
        continue
    fam='hook' if 'hook' in o else ('tool' if 'tool' in o else 'actor')
    (b if fatal is None else a)[fam]+=1
print(fatal,n,dict(b),dict(a))
PY
```

**What a jq census sees vs what is there** (962,681 records total; first fatal at 844,016):

| record family | jq sees | dropped | drop % |
|---|---:|---:|---:|
| `actor` (lead-supervisor pages, `permission_pending`, checkpoints, admission gate) | 775,932 | 97,030 | 11.1 % |
| `hook` (the Stop-path disposition writers) | 65,159 | **20,963** | **24.3 %** |
| `tool` (autonomy-sweep and peers) | 2,924 | 671 | 18.7 % |
| **ALL** | **844,015** | **118,666** | **12.33 %** |

**Excluded strata, named:**

- **`idl.jsonl.chain*` (8 gz + 1 live, 908,190 lines)** — *not JSON*. They are the TSV hash chain
  (`<lineno>\t<sha256>`) and every line fails a JSON parse. A census that globs `idl.jsonl*` and pipes
  it to jq dies at line 1 of the first chain file — a *different*, louder failure than B17's, correctly
  excluded here but worth naming because the glob that produces it is the obvious one to type.
- **Anything before 2026-08-29T09:28Z** — the oldest surviving archive. No claim is made about rotated-out data.
- **The live file's growth after the census prefix** (69,593 lines today vs 54,256 then). Re-running the
  block above reproduces the *ordering*, not the byte-identical file; the fatal record is in an archive,
  so its position shifts as the live file grows. **It carries 0 records > 4,096 B and 0 fatal lines.**
- **The 312 test-fixture rows** A07-sk2 M2 found (`sid` `dbl-1/dbl-3/dbl-4`) are counted here, not filtered.

**One figure from M1 does not reproduce.** M1 reports jq seeing **58,950** hook records; re-executing
jq over the population its own other two figures pin gives **65,159** (rc 5, same fatal line). The
delta is 6,209 and I could not reconstruct it — archives-only ordering gives 47,197, not 58,950. M1's
tolerant side (86,122) is exact, and its corrected magnitudes were computed on the tolerant side, so
**every M1 conclusion stands**; only its jq-side denominator should be read as 65,159.

## 5. Verdict for W3 — CROSSES 90, conviction 96

The producer is unchanged on disk, its deployed copy is the same file, and it emitted 72 oversized
records in the last 11 days including one that actually spliced. This is a live producer defect, so
B17 gets **both** halves the row conditioned on:

1. **The one-line producer fix** — move the 5,763-byte constant `note:` out of the emitted record and
   into a comment beside `autonomy-sweep.sh:1400`, where every other explanation of this length in
   this repo already lives. Record drops 6,679 B → **845 B**. The control arm in §2 is the red-proof:
   pre-fix the defect arm splices, post-fix it must not, under identical concurrency.
   *Residual this does NOT fix:* any future >4,096 B record re-opens it, so the durable form is a
   size assertion in `log_idl`/`idl-log.sh` (refuse or truncate above ~4,000 B) rather than trusting
   each call site. That is a design call for W3, not a blocker on the one-liner.
2. **The tolerant-reader rule for every census** — required *regardless* of (1), because the fix cannot
   repair the 11 days of archives already written. Any jq census over this store must either read
   record-at-a-time and count parse failures as a reported verdict, or use a tolerant reader. jq's rc
   **5** is available and nothing screens it today; `2>/dev/null` on such a census converts a 12 %
   truncation into silence.

Conviction **96** and not higher only because the 1.4 % interleave rate means a fixed producer could
go days without a fatal line — absence of a new fatal record is not evidence the fix worked. Bind the
claim to the control arm, not to the store going quiet.

## 6. What a wrong reading looks like (fail direction)

- **Reading the 4,242-byte fragment as "the record".** It is a *head*, and the brief's "4 KB record"
  inherits that. The real record is 6,679 B, and 4,242 is just where the write happened to be cut —
  chasing a 4 KB size limit finds no such limit anywhere.
- **Concluding "no problem" from the live file.** It has 0 fatal lines and maxlen 1,137 — because §2b
  has not been reached in 30 h under load, not because the producer changed. A census run today over
  `idl.jsonl` alone reads perfectly clean and is 100 % wrong about the store.
- **Blaming escaping, control bytes, UTF-8 or truncation.** All four are the brief's candidates and all
  four are refuted: the two fragments reassemble byte-exactly into valid JSON, and both writers already
  jq-encode every field. Fixing an escaping bug that does not exist leaves the splice live.
- **Blaming `waiting-recycle` / `idl-log.sh`.** Its record is intact and correct; it is the *interloper*
  only because it appended while the oversized write was in two pieces. The size is the actuator.
- **The silent direction is the dangerous one.** jq exits 5 and prints to stderr; a census that
  redirects stderr and ignores rc reports a smaller, internally-consistent number with no tell.
  A07-sk2's own report inherited exactly that and every per-day count matched, which is what made it
  read as corroborated rather than truncated.
