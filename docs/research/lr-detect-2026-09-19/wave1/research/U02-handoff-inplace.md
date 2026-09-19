# U02 — lr-handoff `--in-place`, lr-transplant, the launcher, the ingest prompt, HANDOFF-CONTEXT.md

Unit: U02-handoff-inplace. All paths absolute. Every claim below is `file:line` or `<command> => <output>`.
Subjects read in full: `/Users/chrisren/Development/claude-infrastructure/scripts/limit-recover/lr-handoff.sh` (927 L),
`/Users/chrisren/Development/claude-infrastructure/scripts/limit-recover/lr-transplant.sh` (103 L).

---

## 0. THE HEADLINE — the 4-of-5 PARTIAL rate is ARITHMETIC, not luck

**The watcher makes exactly 2 relaunch attempts inside its 90 s window. `lr-fire-resume`'s capacity
gate has a 3-refusal budget. `2 < 3`, so under sustained load the in-place recycle CANNOT succeed —
by construction, every time, forever.**

The evidence is a single query, and it is unambiguous
(`grep '"caller":"lr-fire-resume"' ~/.claude/autonomy/idl.jsonl | grep 2026-09-19 | jq -c '{ts,verdict,basis,detail}'`):

| sid | attempt 1 (T+0) | attempt 2 (T+45 s) | manual attempt (minutes later) | fleet verdict |
|---|---|---|---|---|
| `d02d8feb` | `17:19:59` refuse — `load 28.65 on 10 cores = 2.86/core > ceiling 2.0/core (refusal **3** of budget 3)` | `17:20:48` **admit** — `budget-expired … load term over after 3 consecutive refusals — admitting and paging: load 27.20 … = 2.72/core` | — | **RECOVERED** |
| `09e64dcb` | `17:22:17` refuse — `2.57/core (refusal 1 of budget 3)` | `17:23:07` refuse — `2.54/core (refusal 2 of budget 3)` | `17:26:24` admit `measured` — load had fallen to `1.61/core` | **PARTIAL** |
| `e442434c` | `17:44:55` refuse — `2.42/core (refusal 1 of 3)` | `17:45:45` refuse — `2.51/core (refusal 2 of 3)` | `17:47:14` admit `headroom-only` — `load term off` | **PARTIAL** |
| `28f07827` | `17:49:47` refuse — `2.05/core (refusal 1 of 3)` | `17:50:37` refuse — `2.12/core (refusal 2 of 3)` | `17:51:43` admit `headroom-only` — `load term off` | **PARTIAL** |
| `cb227486` | `17:53:06` refuse — `4.15/core (refusal 1 of 3)` | `17:53:55` refuse — `6.73/core (refusal 2 of 3)` | `17:55:00` admit `headroom-only` — `load term off` | **PARTIAL** |

**The one success was not a different mechanism — it was a counter that was already at 2.** `d02d8feb`'s
FIRST attempt landed as "refusal 3 of budget 3", i.e. the budget file was pre-charged by earlier
history; its second attempt was the budget release. Load at the moment it was admitted (2.72/core) was
HIGHER than at three of the four refusals that produced a PARTIAL. So load did not discriminate; the
**counter position** did.

Why the counter always starts at 0 for each session: the budget state file is keyed on the **caller**,
not the session (`scripts/lib/capacity-admit.sh:509-514`, `_cc_admit_state_file`
→ `$HOME/.claude/autonomy/capacity-admit/lr-fire-resume.refusals`), and `cc_hw_budget_charge`
**resets it on every admit** (`capacity-admit.sh:955-956`: *"The counter write and the reset both live
in cc_hw_budget_charge"*). Each recovery therefore begins a fresh 1→2→3 ladder, and the watcher retires
at 2. `ls -la ~/.claude/autonomy/capacity-admit/` => `lr-fire-resume.refusals` is `0` bytes (reset by
the `17:55:00` admit).

The constants, in code:

- `scripts/limit-recover/lr-fire-resume.sh:324-329` — gate, and `exit 9` on refusal:
  ```
  if ! cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then
    echo "✗ $(cc_capacity_admit_reason)" >&2
    echo "  Shed load first (close finished panes / let the wave drain), then re-run this exact command." >&2
    echo "  Override for one resume: CC_ADMIT_GATE=off ; raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>" >&2
    exit 9
  fi
  ```
- `scripts/lib/capacity-admit.sh:161` — `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0`; `:581` — `budget="${CC_ADMIT_BUDGET:-3}"`.
- `scripts/handoff-fire.sh:6811` — first wait: `for _ in $(seq 1 15); do sleep 3; …` = **45 s**.
- `scripts/handoff-fire.sh:6812-6816` — ONE retype, then another `seq 1 15` = another **45 s**. Total 90 s, 2 attempts.
- `scripts/handoff-fire.sh:6879` — `!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane`.

The gate sits at `lr-fire-resume.sh:324`, i.e. **before** the `expect` spawn at `:432`. So on all four
PARTIALs the resumed TUI never started, the ingest prompt was never typed, and the failure the operator
saw ("prompt sitting unsent in pane 111") was from a *later manual* attempt, not from this path.

**The fix is one line of the launcher.** The generated launcher (§2) exports `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`
and `CLAUDE_CODE_TASK_LIST_ID` and nothing else. It has no way to say *"this is a limit recovery; the
load term is the wrong input here"* — and `capacity-admit.sh:601` already honours
`CC_ADMIT_LOAD_TERM=off`, which is exactly what all three manual repairs used (`basis:"headroom-only"`,
`detail:"load term off …"`). The lead's `CC_ADMIT_LOAD_TERM=off` in its own shell could never reach
`lr-fire-resume`, because the launcher is typed into *another pane's* shell.

---

## 1. `lr-transplant.sh` — the steps, and the measured cost

Ten steps, all filesystem, **all sub-second**.

| # | step | file:line | measured |
|---|---|---|---|
| 1 | arg parse; require `--sid/--from/--to` | `:17-28` | — |
| 2 | REFUSE if `realpath(from/projects) == realpath(to/projects)` (same account) | `:32-37` | 2 × `python3 -c realpath` ≈ 0.09 s (two interpreter starts) |
| 3 | locate exactly one `$FROM/projects/*/$SID.jsonl`; 0 hits or >1 ⇒ exit 2 | `:39-49` | `ls` glob, <1 ms |
| 4 | REFUSE if destination exists without `--force` | `:55-57` | — |
| 5 | split-brain lock `~/.reso/limit-recover/locks/<sid>.lock`, JSON `{sid,from,to,ts,pid,host}` | `:59-69` | <1 ms |
| 6 | `cp -p` the transcript | `:72` | **0.033 s** for 6,126,267 B (`time cp -p …09e64dcb….jsonl` => `0.033 total`) |
| 7 | `rsync -a` the session dir (subagents/workflows/journals) | `:74-77` | **0.129 s** for 11,672 KB (`time rsync -a …/09e64dcb…/ …` => `0.129 total`) |
| 8 | `rsync -a` `tasks/<task-list>/` when `--task-list` given | `:78-83` | **0.095 s** for 1,020 KB (`claude-infrastructure-main`) |
| 9 | `shasum -a 256` both sides; FATAL on mismatch | `:85-89` | **0.048 s + 0.043 s** on 6.1 MB |
| 10 | tombstone `<sid>.HANDOFF.json` + rename source to `*.jsonl.handed-off` (skipped for the LIVE sid or `--keep-source`) | `:91-100` | <1 ms |

**Total transplant ≈ 0.45 s** on the largest session today. Recorded outcomes — all five `transplant.json`
read `{"ok":true, …,"session_dir_copied":1,"tasks_copied":1,"source_retired":1}`; e.g.
`~/.reso/limit-recover/09e64dcb-16c7-4c65-8b11-fd854d50f299/bundle-20260919T172203Z/transplant.json`:
```json
{"ok":true,"sid":"09e64dcb-…","slug":"-Users-chrisren-Development-claude-infrastructure",
 "target_transcript":"/Users/chrisren/.claude-tertiary/projects/…/09e64dcb-….jsonl",
 "sha256":"380a7f6b342823241310b22f2eaa7947171bcb1a5ef54b5faf3d5ffaac75cbc6",
 "session_dir_copied":1,"tasks_copied":1,"source_retired":1,
 "lock":"/Users/chrisren/.reso/limit-recover/locks/09e64dcb-….lock",
 "tombstone":"/Users/chrisren/.claude-quaternary/projects/…/09e64dcb-….HANDOFF.json"}
```

### The whole pre-launch pipeline is ~3 seconds

From `TS=$(date -u …)` (`lr-handoff.sh:384`) to the last bundle file, by mtime
(`find <bundle> -type f -exec stat -f '%Sm %N' -t '%H:%M:%S'`):

| bundle | TS in dir name | audit.json | last file | elapsed |
|---|---|---|---|---|
| `09e64dcb/bundle-20260919T172203Z` | 12:22:03 | 12:22:04 | 12:22:05 | **2 s** |
| `d02d8feb/bundle-20260919T171945Z` | 12:19:45 | 12:19:46 | 12:19:46 | **1 s** |
| `e442434c/bundle-20260919T174439Z` | 12:44:39 | 12:44:40 | 12:44:41 | **2 s** |
| `28f07827/bundle-20260919T174936Z` | 12:49:36 | 12:49:37 | 12:49:37 | **1 s** |
| `cb227486/bundle-20260919T175254Z` | 12:52:54 | 12:52:55 | 12:52:56 | **2 s** |

Independently timed: `time python3 lr-audit.py --config-dir /Users/chrisren/.claude-tertiary --session
09e64dcb-… --json <scratch>/audit.json --md <scratch>/audit.md --salvage-dir <scratch>/salvage --quiet`
=> **1.115 s** on a 1,657-record / 6.1 MB transcript.

**So audit + bundle + transplant + launcher mint ≈ 3 s. The ~2.5 min per `lr-fleet --one` is ENTIRELY the
recycle watcher's fixed waits.** Measured end-to-end from `handoffs.jsonl`:
success `d02d8feb` `recycle-intent 17:19:47` → `recycle-engaged 17:21:00` = **73 s**;
failure `09e64dcb` `recycle-intent 17:22:06` → fleet verdict `17:23:54` = **108 s**.

Bundle sizes (`du -sk`): 80 KB (`d02d8feb`) · 184 KB (`28f07827`) · 376 KB (`e442434c`) ·
584 KB (`09e64dcb`) · 1,040 KB (`cb227486`). All five `MANIFEST.json` are ~4.4 KB, of which **~3.8 KB
is `source_argv`** — a full `ps -Eww` env dump (SHELL, FPATH, PATH, FNM_*, HOMEBREW_*, KITTY_*, …),
written by `lr-handoff.sh:366` and stored verbatim at `:472,477`.

**A latent defect in that field, visible in the data:** all five `source_argv` values say
`--model claude-opus-5 --effort high`, including the two sessions whose true tier was
`claude-fable-5-1 / xhigh` (`d02d8feb`, `28f07827`, `e442434c`). The argv is the *launcher's*, not the
session's. The transplant only got the tier right because `lr_tier_from_transcript` overrides it
(`lr-handoff.sh:371-381`, `runtime_model`/`runtime_effort` in the manifest are correct in all five).
Keep that read; the `source_argv` blob is 86 % of the manifest and is actively misleading.

---

## 2. The `--in-place` branch

### 2a. The exact `handoff-fire.sh` invocation

`lr-handoff.sh:613-628`:

```bash
HF="$(lrh_hf_bin)"          # beside-script ../handoff-fire.sh → $CLAUDE_CONFIG_DIR/scripts → ~/.claude/scripts  (:597-603)
RCY_ARGS=(--recycle --transplanted-source --resume-launcher "$LAUNCHER" --resume-cfg "$TCFG" --resume-cwd "${WT_TOP:-$CWD}")
if [[ -n "$SOURCE_PANE" ]]; then
  RCY_ARGS+=(--source-pane "$SOURCE_PANE" --source-session "$SID" --await)
fi
"$HF" "${RCY_ARGS[@]}" 2> >(tee "$LRH_RCY_ERR" >&2)
```

Preconditions, all refused early at `:225-235`: `--in-place` requires `--launch`, forbids
`--print-only`, `--no-transplant` (the recycle is admitted on the tombstone the transplant writes) and
`--close-source` (*"two dispositions of the same pane"*). `--source-pane` is bound to the sid through
`~/.claude/cc-registry/<pane>.json` `.session_id` — missing row, missing field, or a mismatch all exit 2
(`:266-284`), and `handoff-fire.sh` re-checks the same row as the actual arbiter (`:261-265`).

Ordering is deliberate: the transplant at `:512-519` runs **before** the recycle, so the lock + tombstone
already exist and are what admit a third-party driver to type `/exit` into a pane it does not own
(`:605-611`).

### 2b. The generated launcher

Minted at `lr-handoff.sh:544-546` via `mktemp "$(lrh_tmpdir)/lr-launch-${SID:0:8}-XXXXXX"` then renamed
with `.sh` (BSD `mktemp` only substitutes a trailing `XXXXXX`). `lrh_tmpdir()` (`:534-539`) prefers
`$TMPDIR`, falls back to `getconf DARWIN_USER_TEMP_DIR`, then `/tmp`. Body written at `:586-594`, every
interpolated field rendered with `printf '%q'` because the file is *source*, not data (`:547-559`).

Today's five, verbatim (`cat /var/folders/0s/…/T/lr-launch-*.sh`); mode `-rwx--x--x`, 758–789 bytes,
**all five still present on disk** (never cleaned up):

```bash
#!/bin/bash
# Resume the handed-off session 09e64dcb-16c7-4c65-8b11-fd854d50f299 on account next3 with the ingest prompt.
# Regenerable: bundle at /Users/chrisren/.reso/limit-recover/09e64dcb-…/bundle-20260919T172203Z
export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH="${CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH:-1}"
export CLAUDE_CODE_TASK_LIST_ID=claude-infrastructure-main
exec /Users/chrisren/.claude/scripts/limit-recover/lr-fire-resume.sh next3 /Users/chrisren/Development/claude-infrastructure 09e64dcb-16c7-4c65-8b11-fd854d50f299 --branch main --model claude-opus-5 --effort high --permission-mode auto --prompt /limit-recover\ ingest\ /Users/chrisren/.reso/limit-recover/09e64dcb-…/bundle-20260919T172203Z
```

The fable one differs only in tier and cwd:
`… lr-fire-resume.sh next2 /Users/chrisren/Development/.worktrees/wt-cc-100046-36511 28f07827-… --branch cc-100046-36511 --model claude-fable-5-1 --effort xhigh --permission-mode auto --prompt /limit-recover\ ingest\ …`

Three properties that matter:

1. **It names `$HOME/.claude/scripts/limit-recover/lr-fire-resume.sh` — the LIVE symlink layer, never
   the worktree** (`$LR` at `lr-handoff.sh:162`), because the launcher outlives the worktree. There is a
   preflight for the consequence at `:496-509`: it greps the LIVE `lr-fire-resume.sh` for each of
   `--branch --model --effort --permission-mode --prompt` and `exit 5`s *before the transplant* if the
   live copy is behind (`LRH_LIVE_PARSER_CHECK=off` kill switch).
2. **It carries no `CC_ADMIT_*`.** That is the whole of §0's defect — the launcher is the only artifact
   that reaches the resume, and it cannot express "recovery".
3. It is run as `bash <launcher>`, **never** `exec bash`, by every path (`:583-585`), so the pane's shell
   survives and the pane stays recyclable. `lr-fire-resume.sh:598-606` closes the same loop from the
   other side: on a tty it falls through to `exec "${SHELL:-/bin/zsh}" -l -i` after the session ends.

### 2c. `handoff-fire rc != 0` — the "relaunch it by hand" path, and the store question

`lr-handoff.sh:645-652`, the exact branch taken 4× today:

```
lr-handoff: --in-place: the recycle did NOT verify (handoff-fire rc=1). The transplant is DONE —
session 09e64dcb now lives under /Users/chrisren/.claude-tertiary and the source pane is a tombstoned
husk (handed-off-session-guard blocks its prompts).
lr-handoff: relaunch it by hand as a NEW pane's own command:  exec /bin/bash /var/folders/…/lr-launch-09e64dcb-6SGtgQ.sh
lr-handoff: then retire the husk:  …/handoff-fire.sh self-close --successor <new-pane-id> --transplanted-source --source-pane 111 --source-session 09e64dcb-…
```
then `echo "$BUNDLE"; exit 4`. (There is a second arm at `:636-644`: if handoff-fire's stderr contains
`has NO shell under its session`, it flips to `LRH_REPLACE=1` — spawn beside the source, retire it via
`--close-source`. Not taken today.)

**ANSWER: the session is effectively INVISIBLE. Four stores could have held it; three do not, and the
fourth actively writes it off.**

| store | what it holds after a `rc=1` in-place PARTIAL | is it swept? |
|---|---|---|
| `~/.claude/logs/handoffs.jsonl` | a `recycle-intent` row and **no outcome row, ever** | **no consumer** |
| `~/.claude/handoff-alarms/` | **nothing** | (swept, but empty) |
| `~/.reso/limit-recover/fleet/<run>/results.tsv` | `…/PARTIAL  transplanted but the relaunch did not verify …` | written + read only by `lr-fleet.sh`; no watchdog |
| `~/.reso/limit-recover/parked/<sid>.json` (the reset poller's queue) | record is **RETIRED as "the successor carries it"** | **anti-swept** |

Receipts:

- **The dangling-intent hole is a code asymmetry, and it is the one arm with no record.** Compare the
  three terminal branches of the watcher in `scripts/handoff-fire.sh`:
  - `:6796-6798` write-failed-twice → `emit_recycle_event recycle-dead` **+** `hf_alarm recycle-relaunch-failed`
  - `:6873-6875` alive-but-never-engaged → `emit_recycle_event recycle-dead` **+** `hf_alarm recycle-dead`
  - `:6878-6880` **no-claude-in-90 s → neither.** Just a comment typed into the pane and `exit 1`.

  Measured, `grep '"gate":"recycle"' ~/.claude/logs/handoffs.jsonl | grep 2026-09-19`:
  ```
  17:19:47 recycle-intent   pane 112   →  17:21:00 recycle-engaged (10s)   ✅
  17:22:06 recycle-intent   pane 111   →  (nothing, ever)
  17:44:42 recycle-intent   pane 121   →  (nothing, ever)
  17:49:38 recycle-intent   pane 114   →  (nothing, ever)
  17:52:57 recycle-intent   pane 117   →  (nothing, ever)
  18:03:45 recycle-intent   pane 121   →  18:04:11 recycle-engaged (5s)    ✅ (the manual repair)
  18:16:11 recycle-intent   pane 114   →  18:18:04 recycle-engaged (10s)   ✅ (the manual repair)
  ```
  Four intents with no terminal state. `grep -rn "recycle-intent" scripts bin hooks tests docs commands`
  finds **no production consumer** that sweeps for intent-without-outcome — only `scripts/drain-recycle-fire.sh:8`
  (a *goal_requested* audit, not a liveness sweep) and test fixtures.
- **No alarms.** `find ~/.claude -maxdepth 3 -name 'alarm-2026091*'` => one file only,
  `~/.claude/handoff-alarms/alarm-20260914T154100Z-76799-18226.json` — five days old. Zero alarms today.
- **The reset poller — the only daemon that could rescue it — writes the husk off by design.**
  `~/Library/LaunchAgents/com.reso.lr-reset-poller.plist` exists.
  `scripts/limit-recover/lr-reset-poller.sh:902-905`:
  ```bash
  if command -v lr_transplanted_to >/dev/null 2>&1 && _lrp_to="$(lr_transplanted_to "$sid" "$cfg")"; then
    log "TRANSPLANTED $sid ($acct) → $_lrp_to; parked record retired (the successor carries it)"
    mv "$pf" "$RESUMED/$(basename "$pf")" 2>/dev/null; rm -f "$PARKED/$sid.notified"; continue
  fi
  ```
  And `lr_transplanted_to` (`scripts/limit-recover/lr-lib.sh:262-273`) returns TRUE on nothing more than
  *"the lock exists AND a transcript exists under the target"* — both true after a PARTIAL. It never asks
  whether a **process** is running it. So a PARTIAL is byte-indistinguishable from a success to the
  poller, and the poller's response is to delete the session from its own queue.

  This is the single highest-leverage fault-tolerance finding: **"transplanted" is being used as a proxy
  for "recovered", and the two diverged in 4 of 5 cases today.** The discriminator already exists and is
  cheap — a `handoffs.jsonl` outcome row, or `lr_registry_live_rows`.

- The husk pane itself is not silent, but its only voice is passive: `hooks/handed-off-session-guard.sh`
  (`:15-16, :66`) reads `<sid>.HANDOFF.json` + the lock and **blocks prompts** in the husk. It fires only
  if a human types into the pane. It is a guard, not a detector.
- `handoff-fire.sh:11794` does grep recycle logs for `no claude process appeared` — but that is inside
  handoff-fire's own drain path, reading `/var/folders/…/handoff-recycle-*.log`, which is a per-uid temp
  file with no sweeper and no retention.

### 2d. Why the relaunch itself "worked" every time — and the retype is provably useless

The per-pane watcher logs (`/var/folders/0s/…/T/handoff-recycle-<pane>-<epoch>-<rand>.log`) are identical
in shape across all four failures, e.g. pane 111:

```
→ armed: __recycle pid=48158 pgid=48158 sid=111 tty=/dev/ttys010
→ pane-probe: __recycle listing rc=0 in 0s shape=json ids=12
→ pane-reachable: 111 enumerated by '/Users/chrisren/.claude/bin/it2 session list --json'
→ pane 111 CONFIRMED at a shell prompt after 6s — typing relaunch
→ folded a re-created source stub (09e64dcb-….jsonl) into its .handed-off record
→ relaunch typed into 111: cd /Users/chrisren/Development/claude-infrastructure && nocorrect bash /var/folders/…/lr-launch-09e64dcb-6SGtgQ.sh
⚠ no claude on /dev/ttys010 45s after relaunch — retyping once
!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane
```

Every mechanical step — pane resolution, `/exit`, shell detection (3–6 s), verified typing — worked.
The failure is 100 % downstream, at `lr-fire-resume.sh:328`'s `exit 9`. And **the retype re-runs the
identical command against a counter that has advanced by one**, which is why it produces refusal 2 of 3
rather than a resume. The `✗ capacity-admit: REFUSING …` message printed into the pane and scrolled; the
watcher never captured it, so its verdict names a symptom (`no claude process appeared`) with no cause.
Cause and verdict live in two stores that have no path to each other
(`~/.claude/autonomy/idl.jsonl` vs the temp log).

---

## 3. The ingest prompt — what it is, and how it is meant to be submitted

**What it is:** one line, built at `lr-handoff.sh:464` —
`INGEST_PROMPT="/limit-recover ingest $BUNDLE"` — carried into the manifest as `ingest_prompt`, and
passed to the launcher as `--prompt "$INGEST_PROMPT"` (`:582`).

**How it is submitted** — inside `lr-fire-resume.sh`'s `expect(1)` program:

1. `--prompt` is flattened to a single line first: `PROMPT=${PROMPT//$'\n'/ }` (`:336`) — *"the composer
   submits on CR; newlines are unsafe here."*
2. Injection is **gated on a READY signal read off the status line** (`:381-385`):
   `LR_RE_READY="$(lr_wrap_re 'for shortcuts')|$(lr_wrap_re 'auto mode on')|$(lr_wrap_re 'shift+tab to cycle')"`.
   `lr_wrap_re` makes the pattern wrap-tolerant — a literal match *"silently DROPPED the injected prompt
   and left the recovered session sitting idle"* in a narrow pane.
3. The injection itself (`:549-559`):
   ```tcl
   -re $env(LR_RE_READY) {
     if {$prompt ne "" && !$injected} {
       set injected 1
       sleep 2
       send "\025"     ;# Ctrl-U — clear the composer
       sleep 1
       send -- $prompt
       sleep 1
       send "\r"
     }
   }
   ```
4. **Submit verification** (`:563-583`) — the part that exists precisely because of the operator's
   symptom. Comment verbatim: *"A leading-/ prompt opens the slash-command autocomplete, which can
   swallow the first CR (menu-select, not submit) — the prompt then sits in the composer forever
   (observed 2026-07-11, ingest prompt stranded)."* It watches for `esc to interrupt` (renders only while
   a turn is running — *"the un-fakeable submitted signal"*), re-sending CR up to 5 times at 6 s timeout
   (≤ 30 s). On failure it prints
   `lr-fire-resume: WARNING — prompt may not have submitted; press Enter in the pane.`

Also in that expect loop, for completeness: the resume-return menu is answered "as-is" not "from summary"
(`LR_ASIS`, `:386`, `:338-350`), folder-trust and the fullscreen upsell are answered via a read-back
`answer_menu` that **parks rather than guesses** if the selector cannot be confirmed (`:531-547`), and
`match_max 200000` (`:447`) is set because a wrapped menu is several KB.

**Three operator-relevant consequences.**

- On the four PARTIALs this code **never executed** — `exit 9` at `:328` precedes `spawn` at `:463`.
  The stranded ingest prompt in pane 111 came from a later manual attempt, not from this path.
- The lead's pane-IO findings are explained by this code: `send "\025"` sends the **raw byte 0x15**
  (Ctrl-U), which the composer honours. `kitty @ send-key ctrl+u` encodes it in the *kitty keyboard
  protocol*, which the TUI does not decode — hence the literal `^[[117;5u` the lead saw. The working
  lever is `kitty @ send-text` with a literal `\x15`/`\r`, not `send-key`.
- The prompt is **`/`-headed**, which is exactly the shape the submit-verify loop exists to rescue, and
  exactly the shape `handoff-fire.sh:6867` names as a cause of a "live but task-less" recycle
  (*"the brief was consumed or rejected (a slash-command-headed payload …)"*). A non-slash ingest prompt
  would remove a whole failure class.

---

## 4. `HANDOFF-CONTEXT.md` — what it contains, and whether a plain limit transplant needs it

**Generated, not authored,** when no `--context FILE` is given (`lr-handoff.sh:397-458`), on the stated
grounds that *"A DRIVER (or the poller) cannot author narrative — the source cannot be asked."*

Five sections, all mechanically derived:

| section | source | size in `09e64dcb`'s bundle |
|---|---|---|
| header + UNRECONSTRUCTED warning | literal | 307 B |
| `## Scope (frozen) — durable DoD store for this repo` | `dod_read_content` from `hooks/lib/dod-path.sh` (`:404-410, :443-444`) | **86,888 B** |
| `## Tier at the limit` | `model … · effort … · permission-mode … · task list …` (`:446-447`) | ~120 B |
| `## Last assistant message before the limit` | inline python, last non-error assistant text before the limit record, `[:2000]` (`:411-438, :449-450`) | ~300 B |
| `## Worktree` | cwd/branch/head/dirty (`:452-453`) | ~180 B |
| `## Next action` | the literal string `UNRECONSTRUCTED — run Step 0 (lr-audit) …` (`:455-456`) | ~180 B |

**The DoD section is 98.9 % of the file, and 99 % of the DoD section is other sessions' history.**
Measured on `~/.reso/limit-recover/09e64dcb-…/bundle-20260919T172203Z/HANDOFF-CONTEXT.md`:

```
wc -lc  =>  421 lines, 87,858 bytes
grep -c '^## 20'  =>  87 dated DoD entries, oldest 2026-07-19T02:34:40Z
lines 5-410  (the DoD dump)        => 86,888 B
lines 411-421 (the 4 real fields)  =>    663 B
```

`dod_read_content` returns the **whole append-only store** (its own header says *"INTEGRATE-only: each
capture APPENDS below; history is never rewritten"*), so every `claude-infrastructure` recovery ships 87
historical scopes reaching back two months, including entries for unrelated toplevels
(`/private/tmp/wt-kitty-overlay`). Only the **last** entry is this session's scope. The worktree bundles
are smaller for the same structural reason, not a different one: `28f07827` = 4,485 B / 10 entries,
`d02d8feb` = 4,281 B.

### Is it needed for a plain limit transplant with no delegated work?

**No — not in its current form, and the bundle's own manifest proves it.** All five today record
`"gaps_at_handoff": 0`, and `audit.json .counts` for `09e64dcb` reads
`{"workflows":1,"subagents":0,"gaps":0,"waiting":0,"recoverable_without_respend":0}` — nothing to salvage,
nothing to re-run. The transplant preserves the *entire transcript* under the same uuid, so the resumed
session already has its own scope, its own last message, and its own worktree state **in context**.
Every field `HANDOFF-CONTEXT.md` supplies is either already in the transcript or in `MANIFEST.json`:

| field | already available where |
|---|---|
| Scope (this session's) | the transcript itself; the last DoD entry |
| Tier at the limit | `MANIFEST.json` `runtime_model` / `runtime_effort` / `permission_mode` |
| Last assistant message | literally the tail of the resumed transcript |
| Worktree | `MANIFEST.json` `worktree` / `branch` / `head` + `git-status.txt` |
| Next action | the literal constant `UNRECONSTRUCTED` — zero information |

**And the token cost is real.** The ingest prompt (`/limit-recover ingest <bundle>`) loads
`commands/limit-recover.md` (**41,464 B**), whose step 2 directs the session to read
`HANDOFF-CONTEXT.md` and `audit.md` (`commands/limit-recover.md:470-471`). For `09e64dcb` that is:

```
41,464 (slash command) + 87,858 (HANDOFF-CONTEXT) + 56,375 (audit.md)  =  185,697 B  ≈ 46K tokens
```

before the recovered session does any work — on a session with **zero gaps**. `audit.md` is 1,229 lines
and is itself dominated by a full `## Task list — 64 open of 187` dump.

**Recommendation for U02's slice:** keep the file (its UNRECONSTRUCTED marker is load-bearing for the
driver-authored case), but (a) emit only the **most recent** DoD entry plus a pointer to the store —
86,888 B → ~1 KB; (b) for a 0-gap transplant, skip `audit.md` in the ingest instruction and let the
manifest's `gaps_at_handoff:0` select a short ingest path; (c) drop `source_argv` from the manifest or
reduce it to the argv head — it is 86 % of the manifest and is *wrong about the tier* in 3 of 5 cases.

---

## 5. Direct answers to the operator's target

| target property | today | blocker |
|---|---|---|
| identify pane from a screenshot | statusline carries account #, ctx %, cwd basename, sha, effort — **no pane id, no sid** | separate unit |
| ONE command | `lr-fleet --one` / `lr-handoff --in-place` already is one command | — |
| near-instant | **pipeline is 3 s**; the 2.5 min is 45 s + 45 s of fixed watcher waits + a `/exit` settle | `handoff-fire.sh:6811, 6815` — poll, don't sleep-block; and the retype is worthless (§0) |
| recycled in place, verified engaged | works when admitted (`recycle-engaged … within 5s / 10s`, 3 of 3 manual repairs) | — |
| never a fire-and-forget husk | **4 of 5 today were exactly that** | `handoff-fire.sh:6878-6880` emits no event and no alarm; `lr-reset-poller.sh:902` retires the record as "the successor carries it" |
| invoking session not blocked | `--await` is added whenever `--source-pane` is given (`lr-handoff.sh:621`), so the driver blocks for the full 90–108 s per session | make `--await` optional for the fleet path and reconcile from `handoffs.jsonl` |
| minimal tokens | ~46K tokens of mandatory reading on a 0-gap transplant | §4 |

**The three highest-leverage, smallest fixes this unit can name, in order:**

1. **`export CC_ADMIT_LOAD_TERM=off` (or `CC_ADMIT_BUDGET=1`) in the generated launcher**, at
   `lr-handoff.sh:586-593`. This alone converts 4 PARTIALs into 4 RECOVEREDs. Justification is already
   written in the tree: `capacity-admit.sh` documents the load term as the wrong input for recovery, and
   it is already off on the Agent-tool path. A recovery is net-zero processes — it replaces a dead TUI.
2. **Emit `emit_recycle_event recycle-dead` + `hf_alarm` on the 90 s branch** (`handoff-fire.sh:6878-6880`),
   matching its two sibling branches. Costs 2 lines; converts an invisible husk into a swept row.
3. **Make `lr_transplanted_to` insufficient for retirement** in `lr-reset-poller.sh:902` — require an
   outcome row or a live registry row for the sid, not merely a lock + a file. Today it is the one daemon
   that could have caught this and it does the opposite.
