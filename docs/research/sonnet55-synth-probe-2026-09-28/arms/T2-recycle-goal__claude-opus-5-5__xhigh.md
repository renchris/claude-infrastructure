# How `--recycle` carries the predecessor's `/goal` to the successor

Short version: in the foreground, `--recycle` resolves the predecessor's session id from the pane (`scripts/handoff-fire.sh:12524`). It then calls `inherit_recycle_goal` once (`:12540`). That function reads the last `goal_status` attachment in the predecessor's own transcript, keeps it only if it is non-terminal, re-validates it and writes it into `FIRE_GOAL` (`:5840-5855`). `FIRE_GOAL` then travels as argv `$8` into a detached `__recycle` re-exec of the same script (`:12628`, `:7158`). That watcher pastes `/goal <cond>` into the pane only after the successor's engagement is confirmed (`:7358-7365`), and then reads the result back from the successor's transcript (`:5905-5908`).

## 1. The read

**Decision function.** `inherit_recycle_goal() { # $1=predecessor-sid → always 0` — `scripts/handoff-fire.sh:5840`. Contract:
- Takes a sid. Its only output is a side effect on the global `FIRE_GOAL`: set at `:5847`, cleared at `:5852`.
- Every path returns 0: `:5842-5846` are all `|| return 0` guards, and `:5854` is `return 0`. So under `set -euo pipefail` (`:343`) it can never abort the recycle.
- It prints `→ goal INHERITED from predecessor $1 …` to stdout on success (`:5849`) and a `⚠ …NOT inherited…` line to stderr on refusal (`:5851`).

**Oracle.** `_inh_cond="$(goal_live_for_sid "$1")" || return 0` (`:5845`). `goal_live_for_sid() { # $1=sid → prints the LIVE condition; rc 1 = none (or terminal, or unreadable)` (`:5809`).

**Predecessor identity.** `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`:12524`), where `$SID` is the pane being recycled ("pane $SID", `:12452`). `cc_sid_for_pane` (`:4955`):
- **Source 1:** the first `"session_id":"…"` in `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` (`:4959-4962`).
- **Source 2**, used only if source 1 is empty: each `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json` (`:4984`). It extracts `pid` (`:4986`), requires the pid to be alive with `kill -0` (`:4988`), requires the process env `ITERM_SESSION_ID` to end in `:$pane` (`:4989-4993`), then takes `sessionId` (`:4994-4995`).
- Otherwise it prints nothing and still returns 0 (`:4997`). The empty sid then hits `[ -n "${1:-}" ] || return 0` (`:5844`), so there is no inheritance and no message.
- This resolution runs in the foreground **before** `/exit`, so the live-pid source can still match the predecessor.

**Roots searched.** `for pdir in $CC_PROJECTS_DIRS` (`:5814`), deliberately unquoted and word-split. The default is `$HOME/.claude/projects $HOME/.claude-next/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects`, and it can be overridden by env (`:416`). A missing root is skipped: `[ -d "$pdir" ] || continue` (`:5815`).

**Locating the file.** `find "$pdir" -name "$sid.jsonl" -type f` (`:5829`) is recursive, so it finds the nested per-cwd `<root>/<project>/<sid>.jsonl`. Each hit is processed in `find` order (`:5816-5817`).

**Record shape.** `grep -a 'goal_status' "$hit" | jq -rc --slurp '[ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty'` (`:5818-5819`). The answer is a top-level JSONL record with `type=="attachment"` whose `.attachment.type=="goal_status"`. Lines that merely mention `goal_status` (prose) are dropped by the `select(.type=="attachment")`.

**Which record wins.** `| last`: the last matching record in file order. `grep` preserves line order, and there is no timestamp sort. It is live only if `(.met // false) or (.failed // false)` is `"false"` (`:5823`). The printed answer is `.condition // ""` (`:5824`). An empty condition then fails `[ -n "$_inh_cond" ] || return 0` (`:5846`).

## 2. `hooks/lib/goal-state.sh` is not used

- `handoff-fire.sh` never sources it and never calls `goal_live_condition`, `_goal_grep` or `goal_liveness`. A grep for `goal-state|goal_live_condition|_goal_grep|goal_liveness` over the file hits only the comment at `:5803`.
- The recycle path uses its own mirror, `goal_live_for_sid` (`:5809-5833`). The comment at `:5803` calls it a "Twin of hooks/lib/goal-state.sh::goal_live_condition"; that name resolves to `hooks/lib/goal-state.sh:60`.

| | lib `goal_live_condition` | fire `goal_live_for_sid` |
|---|---|---|
| Input | a transcript **path** (`goal-state.sh:60`); `~` expanded (`:63`); `[ -f ]` required (`:64`) | a **sid** (`handoff-fire.sh:5809`), resolved by `find` across `CC_PROJECTS_DIRS` (`:5814-5830`) |
| grep leg | `_goal_grep` (`goal-state.sh:66`): a no-match rc 1 is turned into 0, a grep error (≥2) stays 1 (`:52-58`) | bare `grep -a 'goal_status' … \| jq …` (`handoff-fire.sh:5818`) under `set -euo pipefail` (`:343`) |
| Failure handling | `\|\| return 1` (`goal-state.sh:68`); empty → 1 (`:69`) | `\|\| continue` (`handoff-fire.sh:5819`); empty → `continue` (`:5820`). It moves on to the next hit or root. |
| Terminal goal | `\|\| return 1` (`goal-state.sh:70`) | `return 1` (`handoff-fire.sh:5827`); stops the whole search |
| Liveness test and output | same jq expressions (`goal-state.sh:67-71`) | same (`handoff-fire.sh:5819`, `:5823-5824`) |

**What the missing hardening changes.** Nothing, for the inheritance decision:
- For a goal-less transcript, the fire's pipeline returns 1 under pipefail and takes `|| continue` (`:5819`). With `_goal_grep` it would return 0 with an empty `rec` and take `continue` at `:5820`. Same path.
- A grep error (rc 2) also lands on `continue`.
- Either way the function ends `return 1` (`:5832`), and the caller treats every rc 1 the same way: `|| return 0` (`:5845`).
- The lib hardening only matters to a consumer that separates "absent" from "unreadable". Its own comments say that is `goal_liveness` (`goal-state.sh:100-103`). `inherit_recycle_goal` does not separate them.

Two real differences remain:
- **A bad file sends the search onward.** A corrupt or unreadable copy of `<sid>.jsonl` makes the fire consult any other file with the same name in later roots (`continue`). The lib just returns 1 on its single path. And "none", "terminal" and "unreadable" all end in the same silent no-op in `inherit_recycle_goal`: nothing is printed at `:5845-5846`.
- **Trailing newlines are stripped before validation.** The fire prints with `jq -r` plus a newline (`:5824`), and the caller's `$(…)` (`:5845`) strips trailing newlines. The lib strips inside the function with `printf '%s' "$(…)"` (`goal-state.sh:71`). Either way, a condition whose only newlines are trailing reaches the validator already cleaned.

## 3. Precedence vs an explicit `--goal`

- **Mechanism:** the first guard, `[ -z "${FIRE_GOAL:-}" ] || return 0` (`:5842`). Any non-empty `FIRE_GOAL` at call time means the oracle is never consulted.
- **The `--goal` flag** sets it at `--goal) FIRE_GOAL="${2:?--goal needs a condition}"` (`:8950`). `:?` rejects an empty argument, so `--goal ""` cannot be used to suppress inheritance.
- **Other things that trip the same guard:**
  - An inherited environment variable: `FIRE_GOAL="${FIRE_GOAL:-}"` (`:508`) keeps any `FIRE_GOAL` from the caller's environment. Any non-empty value, even whitespace, counts as "explicit" and blocks inheritance.
  - Nothing else assigns `FIRE_GOAL` before `:12540`. The only assignments in the file are `:508`, `:5847`, `:5852`, `:7158` (the watcher), `:8950` and `:12538`.
- **An explicit goal is validated differently from an inherited one.** The top-level `check_goal_arm || exit 1` (`:9015`) makes an invalid explicit goal fatal. An invalid inherited goal is dropped and the recycle continues (`:5850-5854`). I did not confirm the call order between `:9015` and the recycle function.
- **Resume mode reverses the rule:** `if [ -n "$RESUME_LAUNCHER" ]; then FIRE_GOAL=""` (`:12535-12538`) wipes any goal, including an explicit `--goal`. So "explicit wins" does not hold for a `--resume-launcher` recycle (`:8942`).

## 4. The opt-out

- **Name:** `CC_RECYCLE_GOAL_INHERIT`.
- **Default:** `1`.
- **Exact test:** `[ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0` (`:5843`). This is a string `!=` test inside `[ ]`, so only the exact string `0` turns inheritance off.
- **Values that do not turn it off:** `off`, `false`, `no`, `00`, ` 0`, `0 ` and so on, because each differs from `0` as a string. An empty value also keeps it on, because `:-1` replaces it with `1`.
- **A doc gets this wrong.** `docs/research/voluntary-inplace-switch-2026-09-22/A07-clean-code-standards.md:170` says "disabled with `=off`/`=0`". Line `:5843` shows `=off` does not disable it.

## 5. Terminal or absent predecessor goals

The decision is `(.met // false) or (.failed // false)` on the **last** attachment record (`:5823`):

- **Met, failed or cleared stops the search.** `met:true`, `failed:true` and a `/goal clear` marker (`met:true`) all evaluate to `true`. That is not `"false"`, so the oracle returns 1 at `:5827` and does not look at further hits or roots.
  - The same happens if the jq on that line fails, because empty output is not `"false"`.
  - An earlier live record cannot rescue a later terminal one, because only `last` is tested (`:5819`).
- **Never armed keeps the search going.** This covers no `goal_status` attachment in the file, prose-only hits, a grep error, or jq failing on the hits. In each case `rec` is empty or the pipeline returns non-zero, so the code takes `continue` (`:5819-5820`) through the rest of `find`'s hits and the remaining roots, then returns 1 (`:5832`).
- The comment at `:5821-5822`, "stop searching other dirs either way", is accurate only once an attachment record has been found.
- If `jq` is missing, the oracle returns 1 immediately (`:5812`).
- In every one of these cases `inherit_recycle_goal` returns 0 silently (`:5845`).

## 6. Validation of an inherited condition

**Which validator, and how it is called.**
- `check_goal_arm` (`:5734`) takes no arguments. It reads the global: `local cond="${FIRE_GOAL:-}" limit="${GOAL_MAX_CHARS:-4000}"` (`:5735`).
- That is why `inherit_recycle_goal` assigns `FIRE_GOAL="$_inh_cond"` first (`:5847`) and then calls `if check_goal_arm` (`:5848`).

**What it rejects** (each one also writes a refusal row):
- **A newline anywhere:** `nl=$'\n'; case "$cond" in *"$nl"*)` (`:5744-5745`). Reason `payload-goal-arm-multiline` (`:5748`). The arming paste is `"/goal $cond"` (`:5886`); the comment at `:5737-5738` says a CR would submit only the first line.
- **A leading `/`:** `case "$cond" in /*)` (`:5754`). Reason `payload-goal-arm-slash` (`:5756`), because `/goal /x` would read as another command (comment at `:5751-5752`).
- **Length:** `${#cond}` greater than `GOAL_MAX_CHARS` (default 4000) (`:5759-5760`). Reason `payload-goal-arm-cap` (`:5763`). The harness cap itself comes from a comment (`:5761`).

**On refusal:**
- It prints `⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself with /goal in the relaunched session` to **stderr** (`:5851`).
- It sets `FIRE_GOAL=""` (`:5852`) and returns 0 (`:5854`). **The recycle continues.**
- The watcher then receives `""` as `$8` (`:12628` → `:7158`), and `arm_goal` returns at `[ -n "$cond" ] || return 0` (`:5867`). No `goal-arm` row is written.
- The condition text itself is discarded.

**Who can read the announcement.**
- The validator's own `!! --goal condition …` lines (`:5746`, `:5755`, `:5761`) also go to stderr, and they misname the inherited condition as `--goal`.
- All of this goes to the stderr of the **foreground** `handoff-fire.sh`. It is printed before the watcher and its log exist (`:12628`).
- Nothing is sent with `cc-notify`. Compare the recycle gate (`:12502-12503`) and `arm_goal` (`:5892`, `:5897`, `:5902`), which do notify.
- So the successor is never told. On a self-recycle the only reader is the predecessor, which is about to receive `/exit`. The comment at `:12511-12513` says that interrupt kills the Bash tool and its process group.

**Durable record: yes, but misleading.**
- Each reason calls `emit_fire_refusal` (`:5748`, `:5756`, `:5763`), which calls `emit_fire_event refused … refuse <gate>` (`:759`).
- That appends to `$HOME/.claude/logs/handoffs.jsonl` (`:683`, `:711`) with `{engaged:false, refuse_reason:"payload-goal-arm-…"}` (`:703`) and `gate:"payload"` (`payload-*` → `payload`, `:742`).
- It is skipped if `CC_FIRE_REFUSAL_LOG=0` (`:684`) or `jq` is absent (`:686`).
- The row describes "a fire that did NOT happen" (`:758`), yet the recycle went ahead. It carries neither the predecessor sid nor the word "inherited".

## 7. Position in the recycle flow and the transport path

**Immediately before the call:**
- The composer gate (`:12467-12507`).
- `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`:12524`). The same value is also the engagement baseline passed to the watcher as `$6` (`:12628`, `:7156`).

**The only call site** (the only non-definition hit in the file for `inherit_recycle_goal`):
```
12535  if [ -n "$RESUME_LAUNCHER" ]; then
12538    FIRE_GOAL=""
12539  else
12540    inherit_recycle_goal "$rcy_old_sid"
```

**Immediately after:** `RCY_T0="$(date -u +%FT%T)"` (`:12542`) and `pin_term_verdict_for_watcher` (`:12543`).

**The branch that skips inheritance.**
- It is resume mode, meaning `RESUME_LAUNCHER` is non-empty. It defaults to empty (`:501`) and is set by `--resume-launcher` (`:8942`).
- The stated reason is a comment (`:12536-12537`): a same-uuid `--resume` carries the unmet goal with it, so inheriting would arm it twice.
- The code is consistent with that. In resume mode the watcher's `$11` is `${RCY_SOURCE_SESSION:-$rcy_old_sid}` (`:12628`), and engagement is judged with `resume_engaged "$RCY_RESUME_CFG" "$RCY_RESUME_SID"` (`:7358`), so the same session is continued.
- The claim that the harness keeps the goal across `--resume` rests on the comment alone; no code here checks it.

**Transport to the successor:**
1. **Hand-off.** `detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" …` (`:12628`). `detach` runs `python3` with `subprocess.Popen(sys.argv[2:], start_new_session=True, stdout=log, …)` (`:1693-1697`). The condition travels as one raw argv element, with no shell re-parsing.
2. **Gate before `/exit`.** `await_armed` (`:12629`) and `await_pane_proof` (`:12636`) must pass. Otherwise the watcher is killed and the recycle aborts (`:12630-12632`, `:12638-12644`).
3. **Read back.** The re-exec enters `if [ "${1:-}" = "__recycle" ]` (`:6938`) and sets `FIRE_GOAL="${8:-}"` (`:7158`).
   - The index checks out: `$1`=`__recycle`, `$2`=SID (`:6939`), `$6`=old sid (`:7156`), `$7`=marker (`:7157`), `$8`=goal.
   - The watcher does not re-validate it: `check_goal_arm` is called only at `:5848` and `:9015`.
4. **When it is armed: after engagement, not at launch.**
   - After the successor process is up (`:7310`), the watcher polls until `resume_engaged …` or `recycle_engaged "$RSID" "$RCY_OLD_SID" "$RCY_MARKER"` succeeds (`:7358-7359`).
   - It prints `ENGAGEMENT CONFIRMED` (`:7360`), then calls `arm_goal "$IT2" "$RSID" "$FIRE_GOAL"` (`:7365`) with `IT2="$HOME/.claude/bin/it2"` (`:6963`) and no provenance argument.
   - Then it emits `recycle-engaged` (`:7368`).
   - If engagement is never confirmed, the path is `goal_unreachable recycle-unverified` (`:7333`) or `recycle-dead` (`:7397`, `:7446`). That prints `goal NOT armed … verdict=unreachable` and writes a `goal-arm` row, but only when `FIRE_GOAL` is non-empty (`:802-804`).
5. **Arming.**
   - `it2_paste_submit_verified "$it2" "$pane" "/goal $cond"` (`:5886`).
   - rc 3, rc 4 and any other failure give `held`, `mangled` and `abstained`, each with a `cc-notify` to the pane (`:5889-5903`).
   - On rc 0, it polls `goal_armed_for_pane "$pane" "$cond"` every 3 s for up to 45 s (`FIRE_GOAL_VERIFY_INTERVAL` / `FIRE_GOAL_VERIFY_TIMEOUT`, `:5866`, `:5905-5911`). The result is `verdict=set` (`:5907-5908`) or `unverified` (`:5915-5916`).
6. **Proof on the successor.**
   - `goal_armed_for_pane` re-resolves pane → sid, which is now the successor's sid (`:5778`), and searches the same roots with `find` (`:5788-5796`).
   - It requires `.attachment.type=="goal_status" and .attachment.met==false and .attachment.condition==$c` (`:5792`). That is an exact-condition match anywhere in the file, not "last record wins".

## Line-number citations checked against the file

| Where | Claims | What is at that line | Resolves? |
|---|---|---|---|
| `scripts/handoff-fire.sh:4824` | `inherit_recycle_goal (:5089, called at :11070)` | `:5089` "# refusal NAMES each agent…"; `:11070` `claimed="$(cd "$REPO" && "$POOL" claim …` | **No** (actual `:5840` / `:12540`) |
| `CLAUDE.global.md:223` | `scripts/handoff-fire.sh:4676-4684` | `:4676` a comment about `bin/cc-reaper's find_transcript`; `:4684` a `for pdir in $CC_PROJECTS_DIRS; do` outside `:5840-5855` | **No** |
| `hooks/goal-inert-watch.sh:36` | `handoff-fire.sh:4671-4688` | `:4671` "# proves the bug). That silently disabled BOTH stamp-recovery…" | **No** |
| `docs/research/exhaustive-drive-2026-09-08/CRITIC.md:62,305` / `:63` | `4676-4684` / `goal_live_for_sid :4642` | `:4642` is `#` | **No** (actual `:5809`) |
| `docs/research/backlog-pipeline-recon-2026-08-12/recon-wave.md:35,169` | `3778-3800` | `:3778` a `pid_is_cc`/ppid comment | **No** |
| `docs/research/voluntary-inplace-switch-2026-09-22/A03-precheck-healthy-source.md:348` | `:5805`, called at `:11070` | `:5805` is the oracle's header comment | **No** |
| same file `:96` | `goal_live_condition` at `hooks/lib/goal-state.sh:60` | `goal_live_condition() {` | **Yes** |
| `docs/plans/NONLIMIT_RESUME_LADDER.md:753` | `:4994-5009` | `:4994` is inside `cc_sid_for_pane` | **No** |
| `docs/plans/LIVENESS_DETECTOR_FAILNEG.md:208` | `:3574 goal_live_for_sid` | `1:custody) return 0 ;;` (in `engage_rc_consequence`, `:3547`) | **No** |
| `scripts/handoff-fire.sh:663` / `:860` / `:840` | watcher re-exec at `:6241`; invoked at `:8827`; `:5884` | `:6241` is `#`; `:8827` a cc-notify comment; `:5884` an `arm_goal` comment | **No** (actual `:6938` / `:12628`) |
| `scripts/handoff-fire.sh:4407`, `:10697`, `:11341` | `set -euo pipefail` at `(:273)` / `(:197)` | Neither line matched my pipefail grep; the statement is at `:343` | **No** |

I did not check these in-file citations: `:6942` (`:5686`), `:12358` (`:4828`/`:4844`/`:4861`) and `:12552` (`:8543`).

*Scope: I read the snapshot at `/tmp/s55/repo-47c3317eb`, as the harness directed. The brief names `/tmp/o55probe-repo-47c3317eb`; both are the same pinned sha, 47c3317eb.*
