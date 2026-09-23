<!-- arm C = claude-opus-5-5 @xhigh · brief T2-recycle-goal · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

# How `scripts/handoff-fire.sh --recycle` carries a live `/goal` to the successor (snapshot 47c3317eb)

**In short:** the recycle resolves the pane's current Claude Code session id, scans that session's transcript for its last `goal_status` attachment, and puts a live condition into `FIRE_GOAL`. The condition then travels as a command-line argument of the detached watcher process. It is pasted as `/goal <cond>` into the successor only after the successor's first real assistant turn. Every hop below is cited.

## 1. The read

**The decision function.** `inherit_recycle_goal() { # $1=predecessor-sid → always 0` is at `scripts/handoff-fire.sh:5840`.
- Every exit path returns 0: the guards at `:5842`–`:5846` all read `… || return 0`, and the function ends with `return 0` at `:5854`.
- Its only output is a side effect on the global `FIRE_GOAL`: it sets `FIRE_GOAL="$_inh_cond"` at `:5847` and blanks it with `FIRE_GOAL=""` at `:5852`.
- So "inheritance must never fail a recycle" (the comment at `:5836`) is backed by the code.

**The oracle.** `goal_live_for_sid() { # $1=sid → prints the LIVE condition; rc 1 = none (or terminal, or unreadable)` is at `:5809`. It is called as `_inh_cond="$(goal_live_for_sid "$1")" || return 0` (`:5845`).

**How the predecessor's identity is obtained.** The recycle path sets `rcy_old_sid="$(cc_sid_for_pane "$SID")"` at `:12524`. `$SID` is a pane id, not a session id. It comes from one of three places:
- a self-recycle: `SID="${SESSION_ID:-$(self_pane_id)}"` (`:9786`);
- the same value after identity verification: `SID="$HF_VERIFIED_PANE"` (`:9797`);
- the remote form: `SID="$RCY_SOURCE_PANE"` (`:9783`).

`cc_sid_for_pane` (`:4955`) turns the pane id into a session id:
1. **Primary source.** It greps `"session_id"` out of `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` and takes the first match (`:4959`–`:4961`).
2. **Fallback.** It walks `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json` (`:4984`). A file counts only if its pid is alive (`kill -0`, `:4988`) and that process's `ITERM_SESSION_ID` ends in `:$pane` (`:4989`–`:4991`). It then takes `sessionId` (`:4994`).
3. If neither source matches, it prints nothing (`:4997`), and inheritance stops at `[ -n "${1:-}" ] || return 0` (`:5844`).

**Directory roots searched.** The loop is `for pdir in $CC_PROJECTS_DIRS` (`:5814`), and missing directories are skipped (`:5815`). The default at `:416` is `$HOME/.claude/projects $HOME/.claude-next/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects`.

**How the transcript is found.** `find "$pdir" -name "$sid.jsonl" -type f` (`:5829`). This is recursive, so it reaches the nested per-cwd project directory.

**Which record counts as the answer.**
- `grep -a 'goal_status' "$hit"` pre-filters the lines. Then `jq -rc --slurp '[ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty'` selects the record (`:5818`–`:5819`).
- So the answer is a top-level JSONL line of the form `{"type":"attachment","attachment":{"type":"goal_status",…}}`.
- Lines that merely mention `goal_status` (for example assistant prose) are dropped by the `type=="attachment"` filter.

**Which record wins.**
- Within one file, `last` wins: the last matching line in file order. The code compares no timestamps.
- Across files, the first transcript that has any `goal_status` attachment decides, live or terminal (`:5823`–`:5827`). "First" means `CC_PROJECTS_DIRS` order, then `find` order.
- The record is live iff `jq -r '(.met // false) or (.failed // false)'` prints `false` (`:5823`). The oracle then prints `.condition // ""` (`:5824`) and returns 0 (`:5825`).
- If `jq` is missing, it returns 1 (`:5812`), which means silently no inheritance.

## 2. `hooks/lib/goal-state.sh` is not used

- **Not sourced.** A grep of `scripts/handoff-fire.sh` for `goal-state` matches only the comment at `:5803`, which calls `goal_live_for_sid` a "Twin of hooks/lib/goal-state.sh::goal_live_condition … duplicated here deliberately". The recycle uses its own copy, `goal_live_for_sid` (`:5809`).
- **Interface.**
  - `goal_live_condition() { # $1 = transcript path` (`hooks/lib/goal-state.sh:60`) takes a path. It expands a leading `~` (`:63`) and requires the file to exist (`[ -f "$tp" ] || return 1`, `:64`).
  - The fire-path twin takes a session id and locates the file itself across 5 roots (`scripts/handoff-fire.sh:5814`–`:5830`).
- **Shared logic.** The jq program (`goal-state.sh:66`–`68` vs `handoff-fire.sh:5818`–`5819`), the live test (`goal-state.sh:70` vs `:5823`) and the condition extraction (`goal-state.sh:71` vs `:5824`) are the same. Neither one reads `sentinel`.
- **Hardening present only in the library.**
  - `_goal_grep` (`goal-state.sh:52`–`58`) turns grep's no-match exit 1 into 0 (`[ "$_gg_rc" -le 1 ] && return 0`, `:56`) and keeps exit ≥2 as a failure.
  - The fire twin pipes a bare `grep -a 'goal_status'` (`:5818`) under `set -euo pipefail` (`:343`). On no match, the whole pipeline returns 1 and hits `|| continue` (`:5819`).
- **What that difference changes: nothing in the outcome.**
  - In the twin, "grep found nothing", "grep errored", "jq failed" and "matched only prose" all go to `continue` (`:5819`/`:5820`) and end in `return 1` (`:5832`). The caller treats every rc 1 the same way (`:5845`).
  - The library's predicate also collapses absent and unreadable into rc 1 (`goal-state.sh:68`, `:69`).
  - The hardening only matters for `goal_liveness`, which separates the positive result `"absent\t0\tnone\t0\t"` (`goal-state.sh:120`) from a real read failure (`|| return 1`, `:140`).
  - The one behavioural difference in the twin: an unreadable copy does not end the search, because the loop moves on to the next hit or root.
- **Minor.** `:5824` has no `2>/dev/null`, while `goal-state.sh:71` does. Trailing newlines are stripped either way: by `printf '%s' "$(…)"` at `goal-state.sh:71`, and by the caller's `$(…)` at `handoff-fire.sh:5845`.

## 3. Precedence: an explicit `--goal` wins

- **The mechanism.** The first guard in the function is `[ -z "${FIRE_GOAL:-}" ] || return 0` (`:5842`). It runs before the opt-out and before any transcript is read.
- **What sets `FIRE_GOAL` before the call:**
  - the flag: `--goal) FIRE_GOAL="${2:?--goal needs a condition}"` (`:8950`), which rejects an empty value;
  - **the environment**: `FIRE_GOAL="${FIRE_GOAL:-}"` (`:508`) keeps any exported `FIRE_GOAL`, and the usage text says "Env equivalent: FIRE_GOAL" (`:34`).
- A grep for every `FIRE_GOAL` reference found assignments only at `:508`, `:5847`, `:5852`, `:7158`, `:8950` and `:12538`. `:7158` belongs to the separate watcher process (`:6938`). So an ambient exported `FIRE_GOAL` is the only non-flag input that trips the rule, and it does so silently.
- **Validation of either source.** `check_goal_arm || exit 1` runs at `:9015`, after the non-resume block closes at `:9012`. A bad explicit or environment goal therefore aborts the recycle. It never falls back to inheritance.
- **Exception.** In resume mode, `FIRE_GOAL=""` (`:12538`) blanks even an explicit `--goal`, with no message (`:12535`–`:12538`). The explicit goal was still validated at `:9015` first.

## 4. The opt-out

- **Name and default.** `CC_RECYCLE_GOAL_INHERIT`, default `1`: `[ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0` (`:5843`).
- **The comparison.** `:-` treats both unset and empty as `1`. `[ … != 0 ]` is a string test, so **only the exact string `0`** turns inheritance off. `off`, `false`, `no`, `00` and ` 0` all leave it on.
- It is checked after `:5842`, so it never cancels an explicit goal.
- `docs/research/voluntary-inplace-switch-2026-09-22/A07-clean-code-standards.md:170` says this switch is "disabled with `=off`/`=0`". The `=off` half is wrong according to `:5843`.

## 5. Terminal or absent predecessor goals

| Predecessor state | What the oracle does | Keeps searching? |
|---|---|---|
| Met (`met:true`) or failed (`failed:true`) | The predicate is true, so `return 1` (`:5827`) | No, it stops |
| Cleared (`/goal clear`) | Treated as terminal only because the clear record carries `met:true` (see below) | No, it stops |
| Never armed (no attachment record, or only prose) | `rec` is empty, so `continue` (`:5820`); grep no-match also gives `continue` (`:5819`) | Yes: next `find` hit, then the next root (`:5814`), ending in `return 1` (`:5832`) |
| Live but with an empty condition | Prints `""` with rc 0 | n/a: stopped at `[ -n "$_inh_cond" ] || return 0` (`:5846`) |

- **Cleared goals.** The code tests only `.met` and `.failed`; `handoff-fire.sh` never reads `sentinel`. The `sentinel:true met:true` dictionary for a clear is a comment (`goal-state.sh:22`), but `goal_liveness` also encodes it in code (`goal-state.sh:127`, `:130`).
- The comment "stop searching other dirs either way" (`:5821`–`:5822`) is true only once a record exists.
- **Effect in `inherit_recycle_goal`.** `|| return 0` (`:5845`) makes every case above a no-op, and none of the no-op branches `:5842`–`:5846` prints anything.

## 6. Validation of an inherited condition

- **How the validator runs.** `FIRE_GOAL="$_inh_cond"` (`:5847`), then `if check_goal_arm; then` (`:5848`). `check_goal_arm` (`:5734`) takes no arguments and reads the global `FIRE_GOAL` and `GOAL_MAX_CHARS` (default 4000) at `:5735`.
- **What it rejects:**
  - Any newline (`nl=$'\n'; case "$cond" in *"$nl"*)`, `:5744`–`:5749`), because the arming paste submits at the first CR (`:5746`). Trailing newlines were already stripped by the `$(…)` at `:5845`, so only interior newlines are caught.
  - A leading `/` (`:5754`–`:5757`), because the text is pasted as `/goal <condition>` (`:5755`).
  - More than the character limit (`:5759`–`:5765`), because the harness caps the condition and sets nothing (`:5761`).
- **On refusal:**
  - It prints `⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself…` to stderr (`:5851`).
  - It sets `FIRE_GOAL=""` (`:5852`) and returns 0 (`:5854`), so **the recycle continues with no goal**. A flag-supplied goal would get `exit 1` at `:9015` instead.
  - `check_goal_arm` also prints its own messages, which refer to a "`--goal condition`" (`:5746`, `:5755`, `:5761`) the operator never passed.
- **Who can read the refusal.** It runs in the foreground `recycle_fire` (`:12354`, called at `:12964`), before the detach (`:12628`). So its output goes to whoever invoked `handoff-fire.sh`, not to the watcher log (only the watcher's output is redirected, `:1696`–`1697`).
  - On a self-recycle, that is the predecessor session, which is `/exit`-ed next (`:12508`–`:12515`, `:12646`).
  - The successor gets an empty argument 8 (`:12628` → `:7158`). `arm_goal` returns at once on an empty condition (`:5867`), and `goal_unreachable` does nothing when `FIRE_GOAL` is empty (`:802`).
  - So the "re-arm it yourself in the relaunched session" advice never reaches the relaunched session.
- **Is anything recorded?** Yes, but under the wrong label.
  - `check_goal_arm` calls `emit_fire_refusal` (`:5748`/`:5756`/`:5763`), which calls `emit_fire_event refused … refuse <gate>` (`:759`).
  - That appends a row to `$HOME/.claude/logs/handoffs.jsonl` (`:683`, `:711`) with `class:"refused"`, `engaged:false` and `refuse_reason:payload-goal-arm-*` (`:703`). The gate is `payload`, because `payload-*` maps to `payload` (`:742`).
  - Nothing is written if `CC_FIRE_REFUSAL_LOG=0` (`:684`) or `jq` is missing (`:686`).
  - The emitter describes such a row as "a fire that did NOT happen" (`:758`), yet the recycle does happen.
  - The inheritance-specific `:5851` line writes nothing.
  - The later recycle outcome rows carry `goal_requested:false` (`:870`).
- This refusal path is pinned by `tests/handoff-goal-arm.bats:378`–`392`.

## 7. Where the call sits, and how the condition reaches the successor

**Single call site.** `inherit_recycle_goal "$rcy_old_sid"` at `:12540`. The only other hits for the name are the definition (`:5840`) and a comment (`:4824`).

**Before it:**
- The composer gate (`:12470`–`:12506`). A foreign draft means `exit 1` (`:12505`) before inheritance is reached.
- The `rcy_old_sid` lookup (`:12524`). The same session id is also the watcher's engagement baseline (`:12521`–`:12523`); it is passed as argument 6 and becomes `RCY_OLD_SID` (`:7156`).

**The branch that skips inheritance.** `if [ -n "$RESUME_LAUNCHER" ]; then FIRE_GOAL=""` (`:12535`–`:12538`). The stated reason: a same-uuid `--resume` already carries the unmet goal, so inheriting would arm it twice (`:12536`–`:12537`). That reason is a comment. Here the code only shows that resume mode checks engagement on the same session id through `resume_engaged` (`:7358`).

**After it:** `RCY_T0` (`:12542`), then `pin_term_verdict_for_watcher` (`:12543`), then the source-transcript, run-directory and submit-token arguments (`:12555`–`:12620`), then the detach (`:12628`).

**Hand-off.**
- `FIRE_GOAL` is passed positionally: `detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" …` (`:12628`).
- `detach` runs `subprocess.Popen(sys.argv[2:], start_new_session=True, stdout=log, stderr=subprocess.STDOUT)` (`:1692`–`1699`).
- So the condition exists only in the watcher's argv. No file or environment variable carries it.

**Read-back.** `if [ "${1:-}" = "__recycle" ]` (`:6938`), then `FIRE_GOAL="${8:-}"` (`:7158`).

**When the goal is armed.**
1. `/exit` is typed only after `await_armed` succeeds (`:12629`) and the pane-reachability checks pass (`:12638`–`:12646`).
2. The watcher polls for engagement, by default for up to `RCY_ENGAGE_TIMEOUT=180` s (`:7159`, `:7339`).
3. When `recycle_engaged` (`:4029`) confirms engagement, it prints "ENGAGEMENT CONFIRMED … (a real assistant turn, not just a process)" (`:7360`) and then calls `arm_goal "$IT2" "$RSID" "$FIRE_GOAL"` (`:7365`), just before the `recycle-engaged` row (`:7368`).
4. So the goal arrives as a second message, after the successor's first assistant turn, never at launch.

**Inside `arm_goal`.**
- It pastes with `it2_paste_submit_verified … "/goal $cond"` (`:5886`).
- It then polls `goal_armed_for_pane` every 3 s for up to 45 s (`:5866`, `:5905`–`:5912`). That check looks up the pane's current session id (`:5778`) and requires an exact match on `.attachment.type=="goal_status" and .attachment.met==false and .attachment.condition==$c` (`:5792`).
- Verdicts: `set` (`:5907`–`:5908`) or `unverified` (`:5915`–`:5916`). They go to the watcher log (`:1696`–`1697`) and as a `goal-arm` row to `handoffs.jsonl` (`:781`, `:791`).
- If engagement never comes, the watcher calls `goal_unreachable` on the `recycle-unverified` path (`:7333`) or the `recycle-dead` path (`:7397`).

## Line citations elsewhere in the repo that no longer resolve

| Citation | What the cited line holds now | Verdict |
|---|---|---|
| `handoff-fire.sh:4824` "inherit_recycle_goal (:5089, called at :11070)" | `:5089` is a comment about agent refusals; `:11070` is `claimed="$(cd "$REPO" && "$POOL" claim …` | STALE (real: `:5840` / `:12540`) |
| `handoff-fire.sh:6942` "positional siblings at :5686" | `:5686` is a comment ("WHAT WAS ACTUALLY MEASURED") | STALE (real: `:7153`–`:7158`) |
| `handoff-fire.sh:12358` "(:4828, :4844, :4861)" | All three are comments | STALE (real emits: `:7332`, `:7368`, `:7396`) |
| `CLAUDE.global.md:223` `handoff-fire.sh:4676-4684` | `:4676` is a comment about cc-reaper; `:4684` is `for pdir in $CC_PROJECTS_DIRS; do` in an unrelated function | STALE |
| `hooks/goal-inert-watch.sh:36` `:4671-4688` | `:4671` is a stamp-recovery comment | STALE |
| `docs/research/exhaustive-drive-2026-09-08/CRITIC.md:62`–`63`, `:305` (`:4676-4684`, `goal_live_for_sid :4642`) | `:4642` is a bare `#` | STALE |
| `docs/research/backlog-pipeline-recon-2026-08-12/recon-wave.md:35`, `:168`–`169` (`:3778-3800`) | `:3778` is a pid_is_cc comment; `:3800` is `fg=…ps -o tpgid` | STALE |
| Test pointer at `recon-wave.md:35` (`tests/handoff-goal-arm.bats:305`) | Line 305 is blank; the inheritance tests are at `:322`–`398` | STALE |
| `docs/plans/NONLIMIT_RESUME_LADDER.md:753` (`:4994-5009`) | Inside `cc_sid_for_pane` / an argv comment | STALE |
| `docs/plans/LIVENESS_DETECTOR_FAILNEG.md:208` (`:3574 goal_live_for_sid`) | `1:custody) return 0 ;;` | STALE |
| `A03-precheck-healthy-source.md:96`, `:348` (`handoff-fire.sh:5805`, called `:11070`) | `:5805` is inside the oracle's header comment | STALE |
| `A03-precheck-healthy-source.md:96` (`hooks/lib/goal-state.sh:60`) | `goal_live_condition` | RESOLVES |
| `A05-recycle-engagement.md:106` (`:12406-12412` → `:5805`) | `:12406` is `tty="$(as_tty_classified "$SID")"`; `:12412` is "not found in iTerm2" | STALE (real branch: `:12535`–`:12541`) |
| "(:273)" / "(:197)" for `set -euo pipefail` at `:4407`, `:10697`, `:11341` | The actual line is `:343` | STALE |
| `tests/handoff-goal-arm.bats:44`–`45` | Extracts functions by name with a `sed` range, so line drift does not break it | RESOLVES |

One more correction: `CLAUDE.global.md:224` says an inheritance refusal "is printed, never silent". It is printed to stderr of the process about to be exited (§6), and the ledger row it produces is labeled as a fire refusal.