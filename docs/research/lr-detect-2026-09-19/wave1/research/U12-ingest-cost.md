# U12 — what `/limit-recover ingest` costs, what it buys, and the minimal correct form

**Headline.** On today's five transplants the ingest pass bought **zero new information**: all five
bundles already carried `gaps_at_handoff: 0` on disk, and the three sessions that re-ran `lr-audit`
in the target re-derived *exactly* that number. Two of the five never ran ingest at all — they came
up on the harness's own `Continue from where you left off.` and continued correctly, unverified.
So the system already ships the zero-ingest path **by accident**; the work is to make it deliberate
and verified. Cost of the current form: **45 s – 2.2 min and 1.4 M – 3.8 M raw tokens per session of
verification round-trips**, plus **~26 K tokens of permanently resident context** that every later
turn re-reads.

---

## 1. `lr-audit.py` — what it scans, what it writes

`/Users/chrisren/Development/claude-infrastructure/scripts/limit-recover/lr-audit.py` (2,362 lines).

**Scans** (docstring, `lr-audit.py:3-10`): `journal.jsonl`, `agent-*.jsonl`, workflow run-summary
JSON, the lead transcript, `teams/<t>/config.json`, teammate transcripts, brief-declared deliverable
paths — plus git and a **pid census** for `lead_state` (`lr-audit.py:38-56`, the D1 change: liveness
is inherited from the lead process state DEAD / IN-FLIGHT / IDLE, never from file mtime).

**Writes** (`lr-audit.py:2345-2357`): `--json <doc>`, `--md <render>`, `--salvage-dir` (salvage +
team salvage). **Exit codes** (`lr-audit.py:56`): `0` no gaps · `1` gaps present · `2` artifact error.

**`--ledger-only`** (`lr-audit.py:2075-2086`) is the cheap tier — one pass over one file, *"no
workflow globs, no team scan, no git, and no pid census"*, prints the lead ledger as JSON, exit 0.

Measured, this box, on the 6.1 MB 09e64dcb transcript:

```
python3 scripts/limit-recover/lr-audit.py --transcript <t> --config-dir ~/.claude-tertiary --ledger-only
  => real 0.13   (prints last_api_error{kind:"session"}, spawned:1, settled:1, open_delegations:[], nonsuccess_notifications:[])
python3 scripts/limit-recover/lr-audit.py --transcript <t> --config-dir ~/.claude-tertiary --json <out> --quiet
  => real 7.04   counts {'workflows': 1, 'subagents': 0, 'gaps': 0, 'waiting': 7, 'recoverable_without_respend': 0}
```

The script is **not** the cost. 5–7 seconds of Python is noise; the cost is the 5–9 model round
trips wrapped around it.

## 2. `Mode: ingest` — the spec (`commands/limit-recover.md:460-477`)

Four steps, and **step 1 is seven identity assertions** (`:464-469`): `$CLAUDE_CONFIG_DIR` ==
`target_cfg`; `$CLAUDE_CODE_SESSION_ID` == `sid`; lock exists and names this target; transcript PATH
under `target_cfg`; quote its first user message; branch != `pool/*`; run
`~/.claude/hooks/session-continue.sh clear`. Step 2 reads `HANDOFF-CONTEXT.md` **and** `audit.md`.
Step 3 re-runs Step 0 (the full `lr-audit`) *fresh in this location*. Step 4 reports.

**Every assertion in step 1 is a shell predicate.** Not one of them needs a language model.

---

## 3. Measured ingest cost — three sessions that ran it

Boundary = the `/limit-recover ingest` user record → the last assistant text of that turn. Tokens
summed from `message.usage` on assistant records, **deduplicated by `message.id`** (Claude Code
writes one usage block per streamed record; naive summing triples the figure).

| session | acct | ingest record | api msgs | tool calls | wall to idle | input | output | cache_read | cache_create | RAW sum |
|---|---|---|---|---|---|---|---|---|---|---|
| `09e64dcb` (whole turn) | next3 | 17:43:23.755Z | 9 | 8 | **133.6 s (2.23 min)** | 18 | 7,324 | 5,121,553 | 617,110 | **5,746,005** |
| `09e64dcb` (verify prefix, msgs 1-6) | next3 | " | 6 | 6 | 92 s | 12 | 3,587 | 3,185,877 | 613,055 | **3,802,531** |
| `cb227486` (verify prefix, msgs 1-4) | next2 | 17:57:29.547Z | 4 | 4 | 63 s | 8 | 4,222 | 1,084,108 | 365,338 | **1,453,676** |
| `28f07827` (verify prefix, msgs 1-2) | next2 | 17:58:24.891Z | **2** | 6 | 46 s | 34 | 2,780 | 710,268 | 652,708 | **1,365,790** |

Whole turns for the latter two run long (`cb227486` 18.98 min / 13 calls; `28f07827` 17.16 min /
32 calls) **but that is the session resuming its real work**, not ingest — `cb227486` was adjudicating
git-forest, `28f07827` was firing wave-1 briefs. The prefixes above are the honest ingest attribution.

### The dominant term is one cache read of the whole context per round trip

Per-message usage, `09e64dcb` ingest turn (`steps.py` over the transcript):

```
17:43:38  out  431  cache_rd     30,705  cache_cr 593,843   <- transplant: the context is WRITTEN into next3's cache
17:44:06  out  946  cache_rd    624,548  cache_cr   3,574
17:44:19  out  453  cache_rd    628,122  cache_cr   1,700
17:44:32  out  482  cache_rd    629,822  cache_cr     913
17:44:42  out  668  cache_rd    630,735  cache_cr  11,210
17:44:53  out  607  cache_rd    641,945  cache_cr   1,815
17:45:07  out 1554  cache_rd    643,760  cache_cr   1,302
17:45:19  out  653  cache_rd    645,062  cache_cr   1,792
17:45:33  out 1530  cache_rd    646,854  cache_cr     961
```

**Every extra tool call in an ingest turn costs one full-context cache read — ~640 K tokens here.**
The first message's `cache_creation` of 593,843 is the unavoidable price of the transplant itself
(the moved context has to be written into the new account's cache); everything after it is optional.

`28f07827` proves the cheap form is already reachable today: it issued **five Bash calls inside ONE
assistant message** (`hLfGC7pV`, blocks at 17:58:59 / 17:59:01 / 17:59:04 / 17:59:10 / 17:59:12, all
one `message.id`), so it paid **one** 679 K read instead of five. `09e64dcb` serialised its eight
calls and paid eight.

### Base-input-equivalent (Opus 5 ratios: out ×5, cache_read ×0.1, cache_create ×1.25)

| | RAW tokens | base-input-equiv |
|---|---|---|
| `09e64dcb` whole ingest turn | 5,746,005 | 1,320,180 |
| `09e64dcb` verify prefix | 3,802,531 | 1,102,853 |
| `cb227486` verify prefix | 1,453,676 | 586,201 |
| `28f07827` verify prefix | 1,365,790 | 900,845 |
| **three verify prefixes** | **6,622,000** | **2,589,900** |
| a 1-message ingest for each (cache_create only) | ~1,670,000 | ~2,015,000 |
| **saving** | **~4.95 M (−75 %)** | **~575 K (−22 %)** |

Read that honestly: in RAW tokens the cut is 75 %, but cache reads are cheap per token, so the
*priced* cut is ~22 %. **The real wins are wall time, round trips, and permanent context** — not the
raw token headline.

### The permanent context tax — measured

The slash command injects its own body as a meta user record. `09e64dcb.jsonl` line 1671:
**40,539 chars ≈ 10.1 K tokens** (`wc -c commands/limit-recover.md` => 41,464). Tool results added
in that turn: **36,314 chars ≈ 9.1 K tokens** across 8 results, sized
`[5167, 1334, 828, 24865, 1760, 1387, 403, 570]`. Assistant output: 7,324 tokens.

**≈ 26.5 K tokens permanently resident** for the life of the recovered session, re-read on every
later API call. *Derived estimate:* a session that makes another 100 calls pays ~2.65 M extra
cache-read tokens (~265 K base-input-equivalent) for it.

**The single largest item is waste we can name.** The 24,865-char result is the `HANDOFF-CONTEXT.md`
read — and the model's very next sentence discarded it verbatim:

> *"Context transplanted intact — I have the full session. The handoff doc is the repo's durable DoD
> history (marked UNRECONSTRUCTED), not this session's scope; mine is the live `/goal`."*
> — `09e64dcb`, 2026-09-19T17:44:43.175Z

That is structural, not a mistake: `lr-handoff.sh:439-457` writes `HANDOFF-CONTEXT.md` (the else-branch of `:398`, which copies a real one when the session left one) **only for a
session it could not ask**, stamping `UNRECONSTRUCTED` and `## Next action: UNRECONSTRUCTED — run
Step 0 … the driver did not guess one.` A transplant that keeps its whole context already knows
everything the file could say. 88 KB read for zero bits.

---

## 4. What the ingest turns actually DID

`09e64dcb`, all eight calls, verbatim purposes:

| # | 17:4x | what it ran | verdict |
|---|---|---|---|
| 1 | 43:39 | `ls` bundle + `cat MANIFEST.json` | shell-checkable |
| 2 | 44:08 | 5 identity asserts: `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_SESSION_ID`, lock+`transplant.json`, transcript path under target, `git branch --show-current` | **all five shell-checkable** |
| 3 | 44:20 | `cat locks/$SID.lock`, `cat <source_cfg>/…/$SID.HANDOFF.json`, `session-continue.sh clear` | shell-checkable; `clear` is the one real side effect |
| 4 | 44:33 | `head -45 HANDOFF-CONTEXT.md` + headings grep | **discarded by the next sentence** |
| 5 | 44:44 | full `lr-audit.py --json --md --salvage-dir` (5.6 s) | **re-derives `gaps_at_handoff`** |
| 6 | 44:55 | grep the audit md + read `counts` out of the json | reads what #5 wrote |
| 7 | 45:10 | `git ls-tree origin/main` content-verify of its own landed paths | genuinely useful — but this is `/wrap`, not ingest |
| 8 | 45:20 | `wrap-ledger.sh --machine`, `cc-decide list --open`, live-layer greps | genuinely useful — also `/wrap` |

Calls 1–6 = verification. **Calls 1–3 are pure shell. Call 4 is waste. Calls 5–6 re-derive a number
the MANIFEST already holds.** Calls 7–8 are the close ledger and belong to whatever the session does
next, not to ingest.

`cb227486` (13 calls) and `28f07827` (6 in 2 msgs) ran the same first four and then went straight
back to work.

---

## 5. The re-derivation was redundant in 3/3, and skipped entirely in 2/5

`lr-handoff.sh:464-477` writes `gaps_at_handoff` into `MANIFEST.json` from
`jq -r '.counts.gaps' "$BUNDLE/audit.json"` — i.e. **the full audit already ran on the source
transcript, and its verdict is on disk before the session moves.**

Today's five bundles (`jq` over each `bundle-*/audit.json`):

```
09e64dcb {"gaps":0,"waiting":0,"open":0,"spawned":1, "settled":1, "err_kind":"session","lead_state":"IDLE"}
cb227486 {"gaps":0,"waiting":0,"open":0,"spawned":3, "settled":3, "err_kind":"session","lead_state":"IDLE"}
28f07827 {"gaps":0,"waiting":0,"open":0,"spawned":16,"settled":16,"err_kind":"session","lead_state":"IDLE"}
e442434c {"gaps":0,"waiting":0,"open":0,"spawned":15,"settled":15,"err_kind":"session","lead_state":"IDLE"}
d02d8feb {"gaps":0,"waiting":0,"open":0,"spawned":9, "settled":9, "err_kind":"session","lead_state":"IDLE"}
```

Post-ingest audits in the target, same command:

```
09e64dcb audit-174449.json {"gaps":0,"waiting":0,"wf":1,"sub":0, "open_deleg":0}
cb227486 audit-175826.json {"gaps":0,"waiting":0,"wf":1,"sub":0, "open_deleg":0}
28f07827 audit-175906.json {"gaps":0,"waiting":0,"wf":0,"sub":13,"open_deleg":0}
e442434c  (no audit-*.json exists — ingest never ran)
d02d8feb  (no audit-*.json exists — ingest never ran)
```

**3 of 3 re-runs returned the identical verdict. 2 of 5 never ran it.** `grep -o
'"command-args>ingest' <transcript> | wc -l` => `0` for `e442434c` and `d02d8feb`; their recovery
boundary is a harness meta record `Continue from where you left off.` at `e442434c` line 1107,
2026-09-19T17:47:15.825Z and `d02d8feb` line 1134, 2026-09-19T17:20:49.422Z. Both then continued
productively (`d02d8feb`: 68 tool calls, re-keyed the Fly deploy runner, landed `213a1e882`;
`e442434c`: 12 calls, resumed its ship-land watch).

The fleet run log agrees on which is which
(`~/.reso/limit-recover/fleet/one-20260919T17*/results.tsv`):

```
one-20260919T170450Z  d02d8feb  112 112 next4 next2  parked capacity                17:15:48Z
one-20260919T171910Z  d02d8feb  112 112 next4 next2  recycle-in-place/RECOVERED     17:21:05Z
one-20260919T172126Z  09e64dcb  111 111 next4 next3  recycle-in-place/PARTIAL  …husk 17:23:54Z
one-20260919T174403Z  e442434c  121 121 next4 next3  recycle-in-place/PARTIAL  …husk 17:46:35Z
one-20260919T174851Z  28f07827  114 114 next4 next2  recycle-in-place/PARTIAL  …husk 17:51:26Z
one-20260919T175207Z  cb227486  117 117 next4 next2  recycle-in-place/PARTIAL  …husk 17:54:45Z
```

The **only** run that verified clean (`d02d8feb`, RECOVERED) is one of the two that never ingested.
Ingest is currently reached by the *manual repair* path, not the happy path.

⚠️ **Scope limit, stated rather than buried:** all five observations are `gaps == 0`. I have **zero**
observations today of a `gaps > 0` transplant, so nothing here licenses shortening ingest on that
branch. The proposal below is gated on exactly that.

---

## 6. Proposal — the minimal correct ingest

### 6.1 The precondition that licenses it (all machine-checkable, 0 model tokens)

Call it `LR_FASTPATH`. Every clause is a shell predicate over files that already exist at relaunch
time. Name it in one script, `scripts/limit-recover/lr-ingest-verify.sh <bundle>`, rc 0 / 1:

```sh
# A — nothing is owed (from the bundle the handoff already wrote)
jq -e '.gaps_at_handoff == 0'                       "$B/MANIFEST.json"
jq -e '.counts.gaps == 0 and .counts.waiting == 0'  "$B/audit.json"
jq -e '(.delegations.open|length) == 0 and .delegations.spawned == .delegations.settled' "$B/audit.json"
jq -e '.last_api_error.kind as $k | ["session","weekly","monthly_spend"] | index($k)'    "$B/audit.json"
jq -e '(.teams|length) == 0 or ([.teams[].members[]?|select(.verdict=="RUNNING")]|length)==0' "$B/audit.json"

# B — nothing changed under us since the bundle was cut (0.13 s, one pass, no globs/git/pid)
python3 "$LR/lr-audit.py" --transcript "$T" --config-dir "$TCFG" --ledger-only \
  | jq -e '(.open_delegations|length)==0 and (.nonsuccess_notifications|length)==0 and .spawned==.settled'

# C — identity (commands/limit-recover.md:464-469, mechanised)
[ "$CLAUDE_CONFIG_DIR" = "$(jq -r .target_cfg "$B/MANIFEST.json")" ]
[ -f "$TCFG/projects/$PROJ/$SID.jsonl" ]                 # transcript sits under target_cfg
jq -e --arg t "$TCFG" '.target_cfg == $t' ~/.reso/limit-recover/locks/$SID.lock
[ -f "$SRC_CFG/projects/$PROJ/$SID.HANDOFF.json" ]        # source tombstoned
case "$(git -C "$WT" branch --show-current)" in pool/*) exit 1;; esac

# D — the side effect ingest step 1 performs, moved to the shell
~/.claude/hooks/session-continue.sh clear
```

**Where it runs:** inside the generated launcher (`lr-handoff.sh:586-593`), *before* the
`exec lr-fire-resume …` line. The launcher already owns `CLAUDE_CONFIG_DIR`, the worktree and the
sid, so C is fully checkable from outside the session. It writes its receipt to
`$B/INGEST-VERIFIED.txt` (one line per clause, PASS/FAIL, with the values compared).

**Fail-closed:** rc != 0 ⇒ the launcher does **not** substitute the short prompt. It keeps
`--prompt "/limit-recover ingest $BUNDLE"` exactly as today and appends the failing clause to it, so
the degraded path is *named in the prompt the operator can see* rather than silently taken.
That is the one-line change at `lr-handoff.sh:464`:

```sh
if bash "$LR/lr-ingest-verify.sh" "$BUNDLE" > "$BUNDLE/INGEST-VERIFIED.txt" 2>&1; then
  INGEST_PROMPT="$(tail -1 "$BUNDLE/INGEST-VERIFIED.txt")"     # the one verified line, below
else
  INGEST_PROMPT="/limit-recover ingest $BUNDLE — lr-ingest-verify FAILED: $(grep -m1 FAIL "$BUNDLE/INGEST-VERIFIED.txt")"
fi
```

`lr-fire-resume.sh:7` already documents `--prompt "ONE-LINE"`, and `lr-handoff.sh:582` already feeds
it — so nothing downstream changes.

### 6.2 The exact prompt text

One line, ~330 chars, no kill-switch phrase, nothing that needs escaping through the kitty
send-text path:

```
Resumed in place on next3 — same pane, same session 09e64dcb, after a session-limit 429 on next4. lr-ingest-verify rc 0 (config dir, session id, transcript path, lock target, source tombstone, branch, auto-continue cleared) and the audit says gaps 0, waiting 0, 0 open delegations — nothing is owed and nothing re-runs. Continue the interrupted work from where you left off. Full check list and receipt: cat /Users/chrisren/.reso/limit-recover/09e64dcb-16c7-4c65-8b11-fd854d50f299/bundle-20260919T172203Z/INGEST-VERIFIED.txt — re-derive with: bash ~/.claude/scripts/limit-recover/lr-ingest-verify.sh <bundle>
```

Template (fields all present in `MANIFEST.json`):

```
Resumed in place on {target} — same pane, same session {sid:0:8}, after a {err_kind}-limit {status} on {source_acct}. lr-ingest-verify rc 0 (config dir, session id, transcript path, lock target, source tombstone, branch, auto-continue cleared) and the audit says gaps {gaps}, waiting {waiting}, {open} open delegations — nothing is owed and nothing re-runs. Continue the interrupted work from where you left off. Full check list and receipt: cat {bundle}/INGEST-VERIFIED.txt — re-derive with: bash ~/.claude/scripts/limit-recover/lr-ingest-verify.sh {bundle}
```

**Why the receipt path and the re-derive command are load-bearing, not decoration.** This repo's own
always-loaded rule
`~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/narrated-verdict-is-indistinguishable-from-a-computed-one.md`
says a conclusion narrated into a stream reads back as that stream's computed result. A prompt that
merely *asserts* "verified" is precisely that failure. The mitigation is that the line is **emitted by
a script**, carries a file a suspicious session can `cat` in one call, and names the command that
recomputes it — so the normal case spends 0 tool calls and the paranoid case spends 1, instead of
today's 6.

### 6.3 What this costs, per session

| | today (`09e64dcb`) | with `LR_FASTPATH` |
|---|---|---|
| model round trips before real work resumes | 6 (verify) / 9 (turn) | **1** |
| tool calls | 6 / 8 | **0** |
| wall to first real work | 92 s / 134 s | **~10 s** (one assistant message) |
| RAW tokens | 3.80 M / 5.75 M | ~0.60 M (the unavoidable cache_create) |
| permanent context added | ~26.5 K tokens | **~0.1 K** (the prompt line) |
| shell cost | — | 0.13 s ledger + ~0.3 s of `jq` |

Across today's three ingests: **−4.95 M raw tokens (−75 %), −575 K base-input-equivalent (−22 %),
−~4 min wall, −~79 K permanently resident tokens.**

### 6.4 What it does NOT fix

Ingest was **~4.2 min of today's 98.7 min (4.3 %)**. Cutting it to zero is real but it is not where
the 99 minutes went — the parked capacity probe (10.1 min), the shared-checkout `git reset` (7.7 min),
ship-land lock contention (12.5 min) and the pane-io repair loop (13 min) are each larger. Ingest's
case rests on **round trips, permanent context, and one fewer place a typed prompt can strand**, not
on the clock.

---

## 7. Open questions

1. **`gaps > 0` was never observed today.** The fast path must keep the full ingest on that branch,
   and nothing here measures how often that branch fires. `grep -c gaps_at_handoff` over older
   bundles would give the base rate.
2. **`e442434c` / `d02d8feb` never ran `session-continue.sh clear` as part of a recovery.** Whether a
   stale pre-limit auto-continue sentinel survived their transplant is unmeasured; if it can, clause
   D is not merely tidy, it is a correctness fix for the RECOVERED path too.
3. **`lead_state` in the target reads `IN-FLIGHT`/`turn_open: true`** on all three post-ingest audits
   (the session is mid-turn *because it is running the audit*). A precondition that ever keys on
   `lead_state` from inside the session is self-poisoning; clause B deliberately uses
   `--ledger-only`, which runs no pid census.
4. **Parallel-call batching is an independent, zero-design win.** `28f07827` paid 1 cache read for 5
   checks; `09e64dcb` paid 8 for 8. Whatever happens to the fast path, the ingest spec should require
   one Bash call.
