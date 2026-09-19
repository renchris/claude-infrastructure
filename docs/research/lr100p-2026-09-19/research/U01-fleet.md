# U01-fleet — lr-fleet.sh / lr-lib.sh, measured 2026-09-19

Scope: read of `scripts/limit-recover/lr-fleet.sh` (514 ln, all), `lr-lib.sh` (369 ln, all),
`lr-handoff.sh` (927 ln, all), plus the live `scripts/lib/capacity-admit.sh`,
`scripts/handoff-fire.sh` recycle watcher, `bin/claude-accounts` ranker, and today's six fleet runs.
All paths relative to `/Users/chrisren/Development/claude-infrastructure`.

---

## 0. The one-line finding

**4 of today's 5 in-place recoveries died on a 3-refusal capacity budget that the 90-second watcher
can only ever charge TWICE** — so the release is structurally unreachable inside the window, and the
one success was the session that inherited a counter already at 2 from a previous run. Everything
else (60 s census, unrecorded target picks, the DUPLICATE false positive) is cost and blindness
layered on top of that single off-by-one.

---

## 1. `--locate`: what it scans, what it costs, and the DUPLICATE defect

### 1.1 Construction

`lf_locate()` — `lr-fleet.sh:183-250`. Outer loop over `lr_config_dirs()` (`lr-lib.sh:20-27`), which
emits **five** dirs: `~/.claude`, `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary`,
`~/.claude-quaternary`. Inner glob `"$cfg"/projects/*/*.jsonl`. Per file:

| step | line | cost |
|---|---|---|
| `tail -c 20000` + `grep -E "$BLOCK_RE"` + `grep -q isApiErrorMessage` | `lr-fleet.sh:191-192` | 1 tail + 2 grep **per file, all 2,579** |
| `lf_kinds_of` | `:143-162` (called `:193`) | python3 spawn #1 |
| `lf_err_age_s` | `:166-182` (called `:195`) | python3 spawn #2 |
| "limit must be the LAST assistant word" gate | `:197-209` inline | python3 spawn #3 |
| `head -c 8000 … grep '"agentName"'` (TEAMMATE test) | `:211` | 1 head + 1 grep |
| `lr_tier_from_transcript` | `lr-lib.sh:34-74` (called `:213`) | python3 spawn #4, and it reads the **WHOLE** file (`open(sys.argv[1])`, `lr-lib.sh:41`), not a tail |
| `lr_registry_live_rows` | `lr-lib.sh:210-231` (called `:214`) | ≥26 `jq` spawns (one per `cc-registry/*.json`) + 4 more per match |
| `lr_resume_procs` | `lr-lib.sh:233-255` (called `:217`) | 1 full `ps -axo` + 2 awk |
| `lr_transplanted_to` | `lr-lib.sh:262-273` (called `:234`) | 1 sed + 1 ls |

### 1.2 Measured cost — `time bash scripts/limit-recover/lr-fleet.sh --locate`

```
bash scripts/limit-recover/lr-fleet.sh --locate  17.80s user 22.05s system 65% cpu 1:00.38 total
```

**60.38 s wall**, and `sys` (22.05 s) exceeds `user` — this is process-spawn + I/O bound, not compute.

Decomposition (measured separately, same box, same moment):

| stage | measurement |
|---|---|
| files enumerated | **2,579** (`ls $d/projects/*/*.jsonl \| wc -l` per dir: 421 + 421 + 621 + 608 + 508) |
| bytes on disk under those trees | ~10.5 GB (`du -sk`: 2.41 + 0 + 3.23 + 1.94 + 2.92 GB) |
| the `tail -c 20000 \| grep -E` prefilter ALONE, all 5 dirs | **43.78 s wall** (13.83 user / 9.97 sys) = **72 % of the total** |
| files passing the text prefilter | **267** |
| rows actually printed | **9** |
| cost per printed row | **6.7 s/row** |
| `cc-registry/*.json` files | **26**; full jq scan of all of them = **0.16 s** |

**16 % of the scan is pure duplication.** `~/.claude-next/projects` is a symlink:

```
readlink ~/.claude-next/projects => /Users/chrisren/.claude/projects
```

so the 421 files under `~/.claude` are tailed, grepped and (when they hit) python-parsed **twice**.
The dedup — `lf_dedup_mirror`, `lr-fleet.sh:256-260` — runs on the OUTPUT, at `:365`, i.e. after the
entire double scan. The de-duplication is a post-filter where it should be an input filter.

**Guess (labelled):** the ~16.6 s that is not the prefilter is the ~267 survivors' python3/jq/ps
fan-out; I did not time that stage in isolation.

### 1.3 Why DUPLICATE fired on two freshly-RECOVERED sessions — `lr-fleet.sh:217`

```bash
if [ "$n" -gt 1 ] || lr_resume_procs "$sid" >/dev/null 2>&1; then disp=DUPLICATE; else disp=RECOVERABLE; fi
```

`n` = count of live registry rows. The `||` treats *any* success from `lr_resume_procs` as a SECOND
process **without ever checking whether it is the SAME pid as the registry row**. A session that was
recovered by `lr-fire-resume` is by construction launched as `claude … --resume <sid>`, so it
satisfies both halves with one process, and is reported DUPLICATE forever.

Measured live, three sessions recovered today:

```
=== 09e64dcb-16c7-4c65-8b11-fd854d50f299
registry row : 111  37018  claude-tertiary  /Users/chrisren/Development/claude-infrastructure
resume leaf  : 37018                      <- SAME PID
raw ps match : 36913 (ppid 36905)  |  37018 (ppid 36913)
=== d02d8feb-1f9d-42bb-8487-80b726c88950
registry row : 112  52095 ; resume leaf : 52095 ; raw: 51992, 52095
=== cb227486-f06c-46f0-99d2-3e38af3c4f93
registry row : 117  82206 ; resume leaf : 82206 ; raw: 82121, 82206
```

The raw `ps` set always has **two** members — the `cc-close-attrib` wrapper and its `claude` child:

```
36913 36905 bash /Users/chrisren/.claude/bin/cc-close-attrib …/claude --permission-mode auto --model claude-opus-5 --effort high --resume 09e64dcb-…
37018 36913 …/claude --permission-mode auto --model claude-opus-5 --effort high --resume 09e64dcb-…
```

`lr_resume_procs`' leaf filter (`lr-lib.sh:252`) correctly drops the wrapper (it is the direct parent
of a matching pid), returning exactly one leaf. So the wrapper is *why the argv census is non-empty
at all* — but the DUPLICATE verdict does not depend on how many it returned, only that it returned
**something**. The defect is the missing overlap subtraction, full stop.

**The sibling auditor does it right.** `--duplicates` mode, `lr-fleet.sh:494-499`:

```bash
total=$((nrows + nprocs))
while IFS=$'\t' read -r pane pid _ _; do printf '%s\n' "$procs" | grep -x "$pid" >/dev/null && total=$((total-1)); done
[ "$total" -gt 1 ] || continue
```

Same population, one model subtracts the overlap and one does not — which is exactly why `--locate`
said DUPLICATE and `--duplicates` said "(no session is held by more than one live process)".

**The consequence is not cosmetic.** `lr-fleet.sh:399`:

```bash
DUPLICATE) lf_row … "parked" "DUPLICATE — more than one live process; resolve with --duplicates first"; worst=1; continue ;;
```

So a re-run of `--recover` **refuses to touch any session it already recovered**, and sets `worst=1`,
so the run reports `RECOVERY PARTIAL` (`lf_report`, `:358`). The census has no way to express
"recovered" — a successful recovery is indistinguishable from a split brain, in the direction that
blocks the retry. This is precisely the state panes 111 and 121 were in today: the relaunch typed
the ingest prompt but never submitted it, so no new assistant turn existed, so they were still in
the census (`:197-209` gate still true), now holding a `--resume` process → DUPLICATE.

---

## 2. `--one` / `--recover`, step by step, with the constants

### 2.1 `--recover` (`lr-fleet.sh:384-417`)

1. `RUN=$(date -u +%Y%m%dT%H%M%SZ)`; `mkdir -p $FLEET_DIR/$RUN`; truncate `results.tsv`. `FLEET_DIR
   = ${LR_STATE_DIR:-$HOME/.reso/limit-recover}/fleet` (`:68-69`).
2. `lf_locate | lf_dedup_mirror` → `census.tsv` (`:386`) and rendered to stderr (`:387`).
3. Sequential `while read` over the census (`:389-414`) — **one session at a time, no parallelism**.
   Disposition switch (`:391-408`): `RECOVERABLE` proceeds; `IDLE-AFTER-ERROR|RESUME-IN-PLACE`,
   `CWD-GONE`, `TEAMMATE|RESUMING|TRANSPLANTED*` skip; `DUPLICATE` parks with `worst=1`; `NO-PANE`
   proceeds with `pane="-"`.
4. `lf_one` per survivor (`:411`).
5. `$FLEET_DIR/last` ← run dir (`:415`); `lf_report` (`:416`); `exit "$worst"`.

### 2.2 `lf_one` (`:310-340`)

1. `lf_pick_target "$acct" "$tier"` (`:313`) — see §3.
2. Refuse if target == source (`:314`).
3. Split the tier: `case "$tier" in */*) model="${tier%%/*}"; effort="${tier#*/}"` (`:315`).
4. `--dry-run` short-circuits here, printing the command it WOULD run (`:316-319`).
5. **`lf_capacity_wait`** (`:320` → `:282-291`):

```bash
lf_capacity_wait() {
  local waited=0 max="${LR_FLEET_CAP_WAIT_S:-600}" ivl="${LR_FLEET_CAP_IVL_S:-20}"
  command -v cc_capacity_probe >/dev/null 2>&1 || { echo "…proceeding UNGATED" >&2; return 0; }
  while :; do
    if cc_capacity_probe lr-fleet "$1"; then return 0; fi
    if [ "$waited" -ge "$max" ]; then echo "lr-fleet: PARKED on capacity after ${waited}s — …" >&2; return 1; fi
    echo "lr-fleet: capacity not admitted yet — …; waiting ${ivl}s (${waited}/${max}s)" >&2
    sleep "$ivl"; waited=$((waited + ivl))
  done
}
```

   **600 s cap, 20 s interval = up to 30 blocking probes.** `cc_capacity_probe`
   (`capacity-admit.sh:526-533`) is `cc_capacity_admit` with `_CC_ADMIT_PROBE=1`, which makes the
   budget file, the page and the reset inert (`_cc_admit_spend`, `capacity-admit.sh:922-927`). It is
   therefore **non-charging AND non-releasing** — the driver can wait the full 600 s and never
   consume the refusal budget that would let it in. Measured today: run `one-20260919T170450Z`
   started 17:04:50 Z and wrote `parked / capacity` at **17:15:48 Z = 658 s** later.
6. Build argv and run `lr-handoff.sh --sid … --config-dir … --cwd … --target … --launch --in-place
   [--source-pane P] [--model M] [--effort E]` with stderr tee'd to `$rdir/$sid.stderr` (`:321-325`),
   stdout to `$rdir/$sid.stdout` (`:326`).
7. Mechanism classified by **grepping lr-handoff's stderr** (`:328-332`): `REPLACED in place` →
   `replace-in-place`; `fired split pane|fired new kitty window` → `spawn`; else `recycle-in-place`.
8. Verdict from rc (`:333-337`): 0 → `RECOVERED`; **4 → `PARTIAL` "transplanted but the relaunch did
   not verify — source is a tombstoned husk"**; anything else → `FAILED`.
9. `lf_row` appends 8 TAB fields to `results.tsv` (`:341-343`).

### 2.3 What `lr-handoff --in-place` then does

- Preflight: the LIVE `$HOME/.claude/scripts/limit-recover/lr-fire-resume.sh` must parse
  `--branch --model --effort --permission-mode --prompt`, else **exit 5** before any irreversible
  step (`lr-handoff.sh:496-509`).
- Bundle + `lr-audit.py` → `$HOME/.reso/limit-recover/$SID/bundle-$TS/` with `audit.json`,
  `audit.md`, `salvage/`, `HANDOFF-CONTEXT.md`, `MANIFEST.json`, `git-status.txt`, `git-log.txt`
  (`:384-479`).
- **Transplant** (`:512-519`) via `lr-transplant.sh`: writes the split-brain lock
  `~/.reso/limit-recover/locks/<sid>.lock`, `cp -p` the transcript to the target store, writes the
  tombstone `<src>/<sid>.HANDOFF.json`, and `mv`s the source to `<sid>.jsonl.handed-off`
  (`lr-transplant.sh:59-98`). **This is the irreversible step.** Today's lock, verbatim:
  `{"sid":"09e64dcb-…","from":"/Users/chrisren/.claude-quaternary","to":"/Users/chrisren/.claude-tertiary","ts":"2026-09-19T17:22:05Z","pid":46550,"host":"Chriss-MacBook-Pro-3"}`
- Mint the launcher `$TMPDIR/lr-launch-<sid8>-XXXXXX.sh` (`:544-594`).
- `handoff-fire.sh --recycle --transplanted-source --resume-launcher <launcher> --resume-cfg <tcfg>
  --resume-cwd <wt> [--source-pane P --source-session SID --await]` (`:619-628`).

### 2.4 The recycle watcher's constants (`scripts/handoff-fire.sh`)

| constant | line | value |
|---|---|---|
| wait for the pane's shell after `/exit` | `:6605` | `HF_RECYCLE_SHELL_WAIT_S` default **600 s** |
| first wait for a `claude` on the tty | `:6809` | `for _ in $(seq 1 15); do sleep 3` = **45 s** |
| one guarded retype, then wait again | `:6812-6815` | another **45 s** ⇒ **90 s total, 2 attempts** |
| engagement wait once a process exists | `:6844`, `:11788` | `RCY_ENGAGE_TIMEOUT` default **180 s** |

### 2.5 What is recorded where

| artifact | path | written by |
|---|---|---|
| census snapshot | `~/.reso/limit-recover/fleet/<RUN>/census.tsv` | `lr-fleet.sh:386` (only on `--recover`, **not** on `--one`) |
| per-session result row | `…/<RUN>/results.tsv` | `lf_row`, `:342` |
| lr-handoff stderr / stdout | `…/<RUN>/<sid>.stderr` / `.stdout` | `:325-326` |
| pointer to the last run | `…/fleet/last` | `:415`, `:441` |
| salvage bundle | `~/.reso/limit-recover/<sid>/bundle-<TS>/` | `lr-handoff.sh:385-479` |
| transplant lock + tombstone | `~/.reso/limit-recover/locks/<sid>.lock`, `<src>/<sid>.HANDOFF.json` | `lr-transplant.sh:62,93` |
| capacity verdicts (admit AND probe) | `~/.claude/autonomy/idl.jsonl` | `_cc_admit_emit`, `capacity-admit.sh:395-420` |
| capacity refusal counter | `~/.claude/autonomy/capacity-admit/lr-fire-resume.refusals` | `cc_hw_budget_charge`, `capacity-admit.sh:360-373` |
| recycle lifecycle | `~/.claude/logs/handoffs.jsonl` | `emit_recycle_event`, `handoff-fire.sh:814` |
| watcher trace | `$TMPDIR/handoff-recycle-<pane>-<epoch>-XXXXXX.log` | handoff-fire watcher |
| **target-selection rationale** | **NOWHERE** | see §3.3 |

---

## 3. Target selection — why the Fable sessions went to a 98–99 %-weekly account

### 3.1 The code path

`lf_pick_target`, `lr-fleet.sh:294-309`:

```bash
lf_pick_target() { # $1=source account $2=tier
  local kind=general t
  case "$2" in claude-fable-*) kind=fable ;; esac
  [ "$TARGET" != auto ] && { printf '%s' "$TARGET"; return 0; }
  [ -x "$ACCOUNTS" ] || return 1
  t="$("$ACCOUNTS" --rank "$kind" 2>/dev/null | awk -v s="$1" '$1 != s { print $1; exit }' || true)"
  [ "$t" = none ] && t=""
  [ -n "$t" ] || return 1
  printf '%s' "$t"
}
```

The tier arrives slash-joined (`lr-fleet.sh:213`: `lr_tier_from_transcript … | tr ' ' '/'`), e.g.
`claude-fable-5-1/xhigh`, which still matches `claude-fable-*` — the lane selection is correct.

`--rank` emits `acct score` lines on stdout, sorted **descending by score**
(`bin/claude-accounts:3502`, `out.sort(key=lambda x: x[0], reverse=True)`), diagnostics on stderr
(verified: `--rank fable 2>/dev/null` → `next2 0.000009`; `2>&1 1>/dev/null` → the
`claude-accounts: fable excluded — next=fable-exhausted; …` and `route-meta:` lines). So `awk '$1 !=
s {print $1; exit}'` takes the ranker's own top pick unless that pick is the source.

### 3.2 The dry run, verbatim (`~/.reso/limit-recover/fleet/20260919T170307Z/`)

```
d02d8feb-…  112  112  next4  next   dry-run     # census tier claude-fable-5-1/xhigh
09e64dcb-…  111  111  next4  next3  dry-run     # census tier claude-opus-5/high
e442434c-…  121  121  next4  next   dry-run     # census tier claude-fable-5-1/xhigh
609597db-…  -    -    next2  next3  dry-run
c060ddcd-…  -    -    next3  next   dry-run
```

The **fable** lane returned `next`; the **general** lane returned `next3`. The split is by lane, not
by accident: `score_fable` (`bin/claude-accounts:3455-3489`) scores
`f_eff / H**urgency_exp * JB * _soft * _cliff_factor` where
`f_eff = min(coupling * (1 - fable_pct/100), w_rem)` and `H` is the **fable** reset horizon, while
`URGENCY_EXP` defaults to **2.0** (`:1733`) — "deadline-DOMINANT urgency". An account with tiny
headroom but an imminent fable reset therefore *legitimately* outranks one with large headroom and a
far reset. **`next` at 98–99 % general weekly was not a bug in the awk — it was the urgency term
paying off a near-term fable reset against a nearly-spent weekly bucket.** The operator's
`--rank fable` reading and the dry run disagreed because they were taken at different times against
a **90 s-TTL shared cache** (`bin/claude-accounts:141`, `/tmp/claude-accounts-cache.json`).

I can prove the drift but not reconstruct the 17:04 Z ranking: by 17:19 Z the real runs chose
`next2`/`next3` and `--rank fable` today reports `next=fable-exhausted`.

### 3.3 The three real defects here

**(a) The choice is unrecorded.** `lf_pick_target` uses `--rank`, and `bin/claude-accounts:5633-5635`
says so explicitly: *"`--rank` is diagnostic and deliberately silent here: only a `--route` is a
decision something acts on."* `log_route_decision` runs only on `--route`. `~/.claude/autonomy/route.jsonl`
does not exist on this box, and `cc-route` (the recorder for the general/fable lanes) is never on
lr-fleet's path. So the fleet's target picks, their scores, and the exclusion map that produced them
leave **no artifact anywhere** — `results.tsv` records only the winning name. The operator's override
was therefore unfalsifiable in both directions.

**(b) No `--assign` charge ⇒ a burst stacks.** `grep -rn -- "--assign" scripts/ bin/` shows the only
production callers are `handoff-fire.sh:8908` and `:9298`. `lr-fleet.sh` never charges one. The
router's own header calls this out by name (`bin/claude-accounts:1700-1713`): *"Every fire inside the
90s cache TTL then took rank[0] = next2 … same rows, same top pick, nothing decrementing headroom
between fires"*, and `k_phantom` exists to make *"a burst of fires walk DOWN the ranking inside the
cache TTL instead of stacking"* (`ASSIGN_TTL_MIN = 15.0`, `:1732`). `--recover` fires sessions
sequentially at ~2.5 min each, so consecutive picks straddle the TTL unpredictably — sometimes
stacking, sometimes not, and never recorded.

**(c) No validation of the returned token.** Only the literal `none` is rejected (`:306`). Any other
stdout word — a future diagnostic leaking to stdout, a renamed account — passes the `!= source` test
and is handed to `lr-handoff --target`, which only then refuses at `acct_to_cfg` (`lr-handoff.sh:318-319`).
The `none` guard exists because exactly this happened on 2026-09-10 (comment at `:302-305`).

---

## 4. Every exit path that leaves a husk — and what the operator sees

A **husk** = the transplant is DONE (lock + tombstone written, source renamed `.jsonl.handed-off`)
and no live process carries the session.

| # | path | line | rc | what the operator sees |
|---|---|---|---|---|
| H1 | `--in-place` cannot reach `handoff-fire.sh` | `lr-handoff.sh:615-618` | **4** | stderr only: *"The transplant is DONE; relaunch by hand as a NEW pane's own command: exec /bin/bash <launcher>"* |
| H2 | **the recycle did not verify** (any handoff-fire non-zero that is not the launcher-rooted case) | `lr-handoff.sh:645-652` | **4** | stderr: *"the source pane is a tombstoned husk (handed-off-session-guard blocks its prompts)"* + the manual relaunch + the manual self-close command. `lf_one` turns this into `recycle-in-place/PARTIAL` in `results.tsv`. **This is the one that fired 4× today.** |
| H3 | REPLACE-in-place fired but `NEW_PANE` is empty (kitty returned a non-integer, or `osa_type_verified` failed) | `lr-handoff.sh:902-909` | **3** | *"--close-source could NOT identify the pane it created — this pane stays OPEN"* + the self-close command. Not a husk (source survives) but the successor is unverifiable. |
| H4 | `--close-source` cannot reach handoff-fire | `:910-916` | **3** | same shape |
| H5 | kitty split/os-window launched and the window died with the launcher | `:766-769`, `:839-844` | fire demoted, no husk | *"the kitty split window (N) did not survive the launch"* |
| H6 | inside the watcher: **relaunch write failed twice** | `handoff-fire.sh:6792-6798` | 1 | emits `recycle-dead` **and** `hf_alarm recycle-relaunch-failed` |
| H7 | inside the watcher: process appeared, never engaged | `handoff-fire.sh:6872-6876` | 1 | emits `recycle-dead` **and** `hf_alarm recycle-dead` |
| **H8** | inside the watcher: **no claude process appeared within 90 s** | `handoff-fire.sh:6878-6880` | 1 | **no `emit_recycle_event`, no `hf_alarm`** — a shell COMMENT typed into the pane (`# HANDOFF RELAUNCH FAILED — run manually: …`) plus one stderr line |

### 4.1 H8 is the hole, and it is the common case

```bash
  hf_bounded "$IT2" session run -s "$RSID" "# HANDOFF RELAUNCH FAILED — run manually: $(cat "$CMDFILE")" >/dev/null 2>&1 || true
  echo "!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane" >&2
  exit 1
```

Its two siblings (H6, H7) both write a ledger row and raise a durable alarm. H8 writes neither.
Measured in `~/.claude/logs/handoffs.jsonl` for today:

```
17:19:47Z recycle-intent  target_pane=112   → 17:21:00Z recycle-engaged  ✓
17:22:06Z recycle-intent  target_pane=111   → (nothing, ever)
17:44:42Z recycle-intent  target_pane=121   → (nothing)
17:49:38Z recycle-intent  target_pane=114   → (nothing)
17:52:57Z recycle-intent  target_pane=117   → (nothing)
18:03:45Z recycle-intent  target_pane=121   → 18:04:11Z recycle-engaged  ✓  (operator re-drive)
18:16:11Z recycle-intent  target_pane=114   → 18:18:04Z recycle-engaged  ✓  (operator re-drive)
```

Today's class census: `recycle-intent 8 · recycle-engaged 4 · recycle-dead 0 · recycle-unverified 0`.
**Four dangling intents with no terminal row, and zero failure rows.** Any sweeper keyed on
`recycle-dead`/`recycle-unverified` reads today as a clean 4-for-4. The only structural trace of a
husk is *an intent with no terminal row*, which nothing queries — and note the intent row's own
`pane` key is `target_pane`, while the outcome rows use `pane` (`{"pane":"-"}` on all of today's
outcome rows), so even a hand-rolled join is off by a field name.

Panes **111 and 117 never got a terminal row at all** — the operator's manual repair went around
handoff-fire entirely.

### 4.2 What the operator actually saw in a husk pane

`~/.reso/limit-recover/fleet/one-20260919T172126Z/09e64dcb-….stderr`, verbatim:

```
lr-handoff: transplant ok -> /Users/chrisren/.claude-tertiary/projects/…/09e64dcb-….jsonl
lr-handoff: IN-PLACE — recycling pane 111 (registry-bound to 09e64dcb) onto 'next3': same window, same uuid
→ remote in-place resume: pane 111 is PROVEN to hold session 09e64dcb by its registry row (pid 15230 on its tty) …
!! recycle did NOT verify — watcher verdict:
!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane
lr-handoff: --in-place: the recycle did NOT verify (handoff-fire rc=1). The transplant is DONE …
```

and the watcher log `$TMPDIR/handoff-recycle-111-1789838526-F3pUsW.log`:

```
→ pane 111 CONFIRMED at a shell prompt after 6s — typing relaunch
→ folded a re-created source stub (09e64dcb-….jsonl) into its .handed-off record
→ relaunch typed into 111: cd /Users/chrisren/Development/claude-infrastructure && nocorrect bash /var/folders/…/lr-launch-09e64dcb-6SGtgQ.sh
⚠ no claude on /dev/ttys010 45s after relaunch — retyping once
!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane
```

**Note the success case took the retype too** (`handoff-recycle-112-…log`: `⚠ no claude on /dev/ttys000
45s after relaunch — retyping once` → `→ relaunch process up in 112`). All five panes needed the
45 s retype. The bound is marginal against the median success latency, not generous.

---

## 5. Does the driver's environment reach the relaunch? **NO.**

### 5.1 Where the relaunch command is composed — `lr-handoff.sh:586-593`

```bash
cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Resume the handed-off session $(printf '%q' "$SID") on account $(printf '%q' "$TARGET") with the ingest prompt.
# Regenerable: bundle at $(printf '%q' "$BUNDLE")
export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH="\${CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH:-1}"
${SRC_TASK_LIST:+export CLAUDE_CODE_TASK_LIST_ID=$(printf '%q' "$SRC_TASK_LIST")}
exec $(printf '%q ' "${FIRE_ARGV[@]}")
EOF
```

**Exactly two variables are carried: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` and (conditionally)
`CLAUDE_CODE_TASK_LIST_ID`.** The comment at `:583-585` names this as a deliberate whitelist restore.
No `CC_ADMIT_*`, no `CC_ROUTE_*`, nothing else.

The launcher is then executed by the recycle watcher as a line **typed into the pane's own
surviving login shell** (`cd <cwd> && nocorrect bash <launcher>`, watcher log above; the file is run
as `bash <launcher>` — never `exec` — per `lr-handoff.sh:585`). That shell is a fresh `$SHELL -l -i`
(`lr-lib.sh:327-328`), so it inherits the **pane's** environment, never the driver process's. On the
spawn paths the launcher arrives as kitty argv (`lr-lib.sh:327-333`, `lr-handoff.sh:752-756`) — same
conclusion.

⇒ `CC_ADMIT_LOAD_TERM=off` exported in the driver's shell is invisible to `lr-fire-resume`.

### 5.2 What `lr-fire-resume` then does with the load term

`scripts/limit-recover/lr-fire-resume.sh:324`:

```bash
  if ! cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then
    echo "✗ $(cc_capacity_admit_reason)" >&2
    echo "  Override for one resume: CC_ADMIT_GATE=off ; raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>" >&2
```

`cc_capacity_admit` defaults the load term **ON**: `capacity-admit.sh:555`
`[ "${CC_ADMIT_LOAD_TERM:-on}" = off ] || CC_ADMIT_TERMS="load"`, and `:636`
`if [ "${CC_ADMIT_LOAD_TERM:-on}" = off ]; then lpc="n/a"; else … cc_hw_load_verdict …`.

This is the opposite default from the sibling gate the same file documents at `:149-160`: *"the load
term therefore DEFAULTS OFF in capacity_gate() (CC_FIRE_LOAD_TERM) and has been off on the Agent-tool
path since Wave D … the INPUT is wrong, not the number."* Two gates over one bad proxy, opposite
defaults, and the recovery path got the ON one.

### 5.3 The off-by-one that actually killed the four recoveries

`~/.claude/autonomy/idl.jsonl`, `caller=lr-fire-resume`, today, verbatim `detail` fields:

```
17:19:59Z refuse  resume d02d8feb… on next2  load 28.65/10 = 2.86/core > 2.0  (refusal 3 of budget 3)
17:20:48Z admit   resume d02d8feb… on next2  load term over after 3 consecutive refusals — admitting and paging: 2.72/core   ← budget-expired
17:22:17Z refuse  resume 09e64dcb… on next3  2.57/core  (refusal 1 of budget 3)
17:23:07Z refuse  resume 09e64dcb… on next3  2.54/core  (refusal 2 of budget 3)
17:26:24Z admit   resume 09e64dcb… on next3  load 1.61/core                      ← operator's manual 3rd attempt, after the watcher gave up at 17:23:5x
17:44:55Z refuse  resume e442434c… on next3  2.42/core  (refusal 1 of budget 3)
17:45:45Z refuse  resume e442434c… on next3  2.51/core  (refusal 2 of budget 3)
17:47:14Z admit   resume e442434c… on next3  load term off · headroom-only        ← operator, with CC_ADMIT_LOAD_TERM=off in the PANE's shell
17:49:47Z refuse  resume 28f07827… on next2  2.05/core  (refusal 1 of budget 3)
17:50:37Z refuse  resume 28f07827… on next2  2.12/core  (refusal 2 of budget 3)
17:51:43Z admit   resume 28f07827… on next2  load term off · headroom-only        ← operator
17:53:06Z refuse  resume cb227486… on next2  4.15/core  (refusal 1 of budget 3)
17:53:55Z refuse  resume cb227486… on next2  6.73/core  (refusal 2 of budget 3)
17:55:00Z admit   resume cb227486… on next2  load term off · headroom-only        ← operator
```

**The pattern is exact and it is arithmetic, not luck.**

- The watcher makes **two** attempts (t=0 and t≈45 s; measured gaps 50 s, 50 s, 50 s, 49 s).
- `CC_ADMIT_BUDGET` defaults to **3** (`capacity-admit.sh:581`), and the release fires only when the
  counter **exceeds** the budget (`cc_hw_budget_charge`, `:367`: `if [ "$n" -gt "$budget" ]`).
- So the release needs a **4th** evaluation. The watcher never makes a 3rd.
  **The budget release is unreachable inside the watcher's window, by construction.**
- The one success, `d02d8feb`, hit `refusal 3 of budget 3` on its *first* watcher attempt and
  `budget-expired` on its *second* — because the counter is **global, per-caller, and persistent**:

```
_cc_admit_state_file "$caller"  → ${CC_ADMIT_STATE_DIR:-$HOME/.claude/autonomy/capacity-admit}/<caller>.refusals   (capacity-admit.sh:510)
ls ~/.claude/autonomy/capacity-admit/
  agent-tool.refusals=3  boot-resume-launch.refusals=1  lr-fire-resume.refusals=(empty)  reso-resume-one.refusals=3
```

  One file for every `lr-fire-resume` invocation on the box, ever, zeroed by `_cc_admit_reset` on any
  admit (`:516`). `d02d8feb` inherited a counter already at 2 from the parked 17:04 run; the admit at
  17:20:48 reset it to 0, and `09e64dcb` — the very next recovery — started again at 1 and died.
  **The single success was an artifact of a shared mutable counter, not of the design working.**
  The ledger even shows the counter surviving across days: `2026-09-17T23:58:51Z … (refusal 2 of budget 3)`.

### 5.4 Two more observations on the same axis

- The driver's `lf_capacity_wait` probe and the pane's `cc_capacity_admit` are **two evaluations of
  the same box, 60–600 s apart, with different term sets** (the driver had the load term off today;
  the pane had it on). The driver can therefore admit and the pane refuse — which is exactly what
  happened, and the driver has no way to learn it.
- The refusal is not silently swallowed: `lr-fire-resume.sh:325-327` prints `✗ …` **into the pane**.
  But it prints it into a pane the operator is not watching, and nothing reads it back: `lf_one`
  classifies solely on `lr-handoff`'s rc and on grepping `lr-handoff`'s own stderr
  (`lr-fleet.sh:328-337`), neither of which ever sees the pane's text.

---

## 6. Numbers a rebuild should have to beat

| quantity | today | source |
|---|---|---|
| `--locate` wall | **60.4 s** | `time bash scripts/limit-recover/lr-fleet.sh --locate` |
| files scanned to print 9 rows | **2,579** (421 of them twice) | `ls */projects/*/*.jsonl \| wc -l`; `readlink ~/.claude-next/projects` |
| share of that in the `tail\|grep` prefilter | **72 %** (43.8 s) | isolated re-run |
| pane→session index cost | **0.16 s** for 26 rows | `time (for f in ~/.claude/cc-registry/*.json; do jq …)` |
| driver capacity park ceiling | **600 s** @ 20 s | `lr-fleet.sh:283` |
| observed park | **658 s** | run `one-20260919T170450Z`, row 17:15:48 Z |
| watcher relaunch window | **90 s / 2 attempts** | `handoff-fire.sh:6809,6812-6815` |
| refusals needed for the budget release | **4** (`n > budget`, budget 3) | `capacity-admit.sh:367,581` |
| in-place success rate today | **1 / 5** (20 %) | six `results.tsv` under `~/.reso/limit-recover/fleet/one-20260919T17*` |
| husk failures with a ledger row or alarm | **0 / 4** | `handoffs.jsonl` class census |
| target picks with a recorded rationale | **0** | `--rank` is silent (`bin/claude-accounts:5633-5635`); no `route.jsonl` on this box |

---

## 7. The shortest fixes implied by the above (each one-line-ish, no design work)

1. `lr-fleet.sh:217` — subtract the overlap exactly as `:497` already does, so a recovered session is
   `RECOVERABLE`/`RECOVERED`, not `DUPLICATE`.
2. `lr-lib.sh:20-27` — skip `~/.claude-next` when `projects` resolves to the same realpath as
   `~/.claude`: 16 % of the census for free, and `lf_dedup_mirror` becomes a belt.
3. Give `--locate` a `--pane N` / `--sid P` fast path that reads `~/.claude/cc-registry/*.json`
   (0.16 s, 26 rows, carries `paneUUID`+`session_id`+`cwd`+`account`+`pid`) instead of the 2,579-file
   sweep. The screenshot's statusline (`(4) 52% · wt-cc-095358-75429 (06ce6fee5) · xhigh`) matches a
   registry row on `account` + `basename(cwd)`; what the registry lacks to disambiguate three panes
   sharing `claude-infrastructure` is **model/effort and the git sha** — both are already in the
   transcript and in `ps`, neither is in the registry row.
4. `lr-handoff.sh:590-591` — add a passthrough of `CC_ADMIT_*` (at minimum `CC_ADMIT_LOAD_TERM`) into
   the launcher, or set `CC_ADMIT_LOAD_TERM=off` there unconditionally to match the Agent-tool path's
   own documented verdict at `capacity-admit.sh:149-160`.
5. `handoff-fire.sh:6878-6880` — emit `recycle-dead`/`recycle-relaunch-failed` and `hf_alarm` on this
   branch, as both siblings already do, and put the pane in a field (`target_pane`) that joins with
   the intent row.
6. Either raise the watcher to 3+ attempts or lower `CC_ADMIT_BUDGET` for this caller, so the
   documented release is reachable inside the window; and key the counter per-recovery rather than
   per-caller-per-box.
7. `lr-fleet.sh:301` — charge `claude-accounts --assign "$t" --src lr-fleet` after the pick, and
   record the ranker's stdout+stderr into the run dir so the choice is replayable.
