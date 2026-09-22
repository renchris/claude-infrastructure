<!-- arm B = claude-opus-5-5 @high · brief T2-recycle-goal · raw worker output, verbatim -->

# How `scripts/handoff-fire.sh --recycle` carries a predecessor's live `/goal` to its successor (snapshot 47c3317eb)

All citations are `scripts/handoff-fire.sh` unless another file is named. **Limit on this answer:** I had only Read available, with no Grep or Glob. Claims of the form "X is not called anywhere" are therefore limited to the call chain I read end to end. They are not a whole-file grep.

---

## 0. Stale line citations (check these first)

| Where the citation is | What it claims | What is actually at that line | Where the code really is |
|---|---|---|---|
| `:4824` (comment in the self-retire block) | "inherit_recycle_goal (:5089, called at :11070)" | `:5089` is prose inside the subagent stop-record comment ("FAILURE DIRECTION IS DELIBERATE…"). `:11070` is `claimed="$(cd "$REPO" && "$POOL" claim "$WORKTREE" …)` in the worktree-pool arm. | **Neither resolves.** Definition is at `:5840`, the only call at `:12540`. |
| Global instructions loaded into this session (text "`inherit_recycle_goal`, `scripts/handoff-fire.sh:4676-4684`") | inheritance code | `:4674-4684` is the `transcript_for_sid` comment and definition (`transcript_for_sid() { # $1=session-id → echoes path or nothing`, `:4679`). | **Does not resolve.** I did not read `CLAUDE.global.md` in the snapshot, so I have not confirmed that this text lives there. |
| `:10697`, `:11341` | `set -euo pipefail` "(:197)" | `:190-213` is the usage/Options header | `:343` `set -euo pipefail` |
| `:5162-5163` | CC_PROJECTS_DIRS: ":399 always SETS the variable" | `:399` is the PANE-SPAWN LOG header | `:416` `CC_PROJECTS_DIRS="${CC_PROJECTS_DIRS:-…}"` |
| `:12552` | PROMPT_FILE "is rewritten … at :8543" | `:8543` is a self-close successor-pin `echo` | `:10846-10847` (`PROMPT_FILE_ORIG="$PROMPT_FILE"` / `PROMPT_FILE="$PF_NB"`) |
| `:644-648` | rewrite at ":7416-7417"; payload_lint_gate ":8973 and :9021" | `:9021` is `echo "!! invalid branch name for --worktree…"` | rewrite `:10846-10847`; payload_lint_gate `:12908`, `:12963`, `:12974` |
| `:662-670` | watcher re-exec ":6241", RCY_PROMPT_FILE ":6248", recycle-intent ":11062" | none of these | `__recycle` guard `:6938`, `RCY_PROMPT_FILE="${9:-}"` `:6945`, `recycle-intent` `:12378` |
| `:6942` | positional siblings "at :5686" | `:5686` is inside the two-message `--goal` comment | `:7153-7158` |
| `:7404-7405` | ":6796 relaunch-write-failed, :6699 pane-vanished, :6873 never-engaged" | stale | `:7191-7192`, `:7076-7077`, `:7396-7398` |
| `:12357-12358`, `:12372` | ":4828, :4844, :4861", ":8788" | `:4828` is self-retire prose | recycle-event sites are in `:7076-7447` |
| `:9678-9686` | explicit arm ":9701", auto arm ":9706", fire charge ":9975", equality ":9474" | stale | explicit arm `:9858-9862`, auto arm `:9863`, charge `:10132-10134`, equality `:9593` |
| `:11232`, `:11237` | RECYCLE_RELOC ":6690", WANT_SELF_RETIRE ":7358" | stale | `:9735`, `:10617` |
| `:12729` | self-close twin ":4104" | stale | `:8894-8902` |

---

## 1. The read

**The decision function** is `inherit_recycle_goal`, defined at `:5840`: `inherit_recycle_goal() { # $1=predecessor-sid → always 0`.
- Its contract is side-effect only. It changes the global `FIRE_GOAL` (`:5847`, `:5852`) and every path returns 0 (`:5842-5846`, `:5854`), so it can never fail the recycle.

**The oracle** is `goal_live_for_sid`, defined at `:5809` and called at `:5845`: `_inh_cond="$(goal_live_for_sid "$1")" || return 0`.

**How the predecessor is identified.** The recycle path does not use a session-id flag. `recycle_fire` resolves the pane's current session id in the foreground, just before the call: `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`:12524`). The result is passed as `$1` at `:12540`.
- `cc_sid_for_pane` first greps `"session_id"` out of the pane's registry row, `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` (`:4959-4962`).
- If that misses, it scans `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json`. It takes a row only if its `pid` is alive (`kill -0`, `:4988`) and that process's `ITERM_SESSION_ID` ends in `:<pane>`; it then returns that row's `sessionId` (`:4984-4995`).
- It always returns 0. Empty output means no inheritance, silently: `[ -n "${1:-}" ] || return 0` (`:5844`).
- The same pane→session lookup already ran once earlier as `RCY_SUBAGENT_SID` (`:9835`). The inheritance path re-reads it rather than reusing that value.

**Which roots are searched.** `for pdir in $CC_PROJECTS_DIRS` (`:5814`).
- The default is five roots: `$HOME/.claude/projects`, `.claude-next`, `.claude-secondary`, `.claude-tertiary` and `.claude-quaternary`, each with `/projects` (`:416`). It can be overridden from the environment.
- A root that is not a directory is skipped (`:5815`).

**How the file is found.** `find "$pdir" -name "$sid.jsonl" -type f` (`:5829`), fed into the `while read` loop.
- This search has no depth limit. `transcript_for_sid` uses `-mindepth 2 -maxdepth 2` (`:4690`); this does not.
- It finds the nested `<root>/<project-slug>/<sid>.jsonl` layout.

**Which records count.** The pipeline is `grep -a 'goal_status' "$hit" | jq -rc --slurp '[ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty'` (`:5818-5819`).
- Only transcript lines whose `.type` is `"attachment"` and whose `.attachment.type` is `"goal_status"` count. Prose that merely mentions `goal_status` is filtered out.
- The fields read from the record are `.met`, `.failed` and `.condition` (`:5823-5824`). `sentinel` is never consulted.

**Which record wins.**
- Within a file, the last matching attachment in file order wins (jq `last`, `:5819`). This is across the whole file, not "since the last arm".
- Across files, the first transcript that yields any such record decides the answer, for both live and terminal goals (`:5821-5827`). Roots are tried in `CC_PROJECTS_DIRS` order. Within a root, `find` output order decides.

## 2. `hooks/lib/goal-state.sh`: not on this path

The recycle chain is `:12540` → `inherit_recycle_goal` (`:5840-5855`) → `goal_live_for_sid` (`:5809-5833`). That chain contains no call to `goal_live_condition` and no `source` of `goal-state.sh`. It uses its own copy, which its header describes as a "Twin of hooks/lib/goal-state.sh::goal_live_condition … duplicated here deliberately" (`:5801-5806`).

How the two differ:

- **Interface.**
  - `goal_live_condition` takes a transcript path. It expands a leading `~` and requires `-f` (`goal-state.sh:60-64`).
  - `goal_live_for_sid` takes a session id and does its own search across roots (`:5809-5831`).
- **Hardening against grep's "no match" status.**
  - The library runs grep through `_goal_grep`. That wrapper turns grep's rc 1 (no match) into success while keeping rc ≥2 (grep error) as failure (`goal-state.sh:52-58`, used at `:66`). So "no goal lines" gives jq an empty input: `--slurp` yields `[]`, the result is empty, and the function returns 1 (`goal-state.sh:69`).
  - `goal_live_for_sid` uses a bare `grep -a … | jq` inside `$(…) || continue` (`:5818-5819`). The script runs under `set -euo pipefail` (`:343`). So a no-match, a grep error and a jq parse failure all make the assignment fail, and all three go to `continue`.
- **What the difference changes.**
  - For a single file, the answer is the same: "no inheritable goal" (rc 1 in the library, eventually `return 1` at `:5832` here). No false inheritance can result.
  - What does change is search termination. A file with no goal lines, or an unreadable one, does not stop the search here; the next `find` hit or the next root is tried. So if the same `<sid>.jsonl` exists under two roots, a copy with no goal lines is skipped and a later copy decides.
  - Everything else is the same in both: the same jq filter, the same `last`, the same met/failed test (`goal-state.sh:67-70` vs `:5819`, `:5823`). Neither checks `sentinel`.

## 3. An explicit `--goal` wins, and what else trips that rule

- The first guard is `[ -z "${FIRE_GOAL:-}" ] || return 0` (`:5842`). Any non-empty `FIRE_GOAL` stops inheritance.
- `--goal` sets it: `FIRE_GOAL="${2:?--goal needs a condition}"` (`:8950`). The `:?` means `--goal ""` aborts, so an empty flag cannot be used to turn inheritance off.
- **An exported environment variable also sets it.** The default is seeded from the environment: `FIRE_GOAL="${FIRE_GOAL:-}"` (`:508`). An inherited `FIRE_GOAL` therefore counts as "explicit". It is also validated before any side effect by `check_goal_arm || exit 1` (`:9015`), so a malformed inherited environment value refuses the whole recycle.
- **The exception: explicit does not win in resume mode.** `if [ -n "$RESUME_LAUNCHER" ]; then FIRE_GOAL=""` (`:12535-12538`) clears even an explicit `--goal`.

## 4. The opt-out

- The variable is `CC_RECYCLE_GOAL_INHERIT`. It defaults to `1`. The test is `[ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0` (`:5843`).
- This is a string comparison against `0`. Only the exact value `0` turns inheritance off.
- `off`, `false`, `no`, `00` and ` 0` all leave it on. Unset or empty also leaves it on, because `:-` substitutes `1`.
- Sibling switches in the same file do accept `off|0|false|no`: `CC_RECYCLE_REPICK` (`:9554`) and `CC_RECYCLE_SUBAGENT_GATE` (`:5185-5186`). This one does not.

## 5. Terminal or absent predecessor goals

- The oracle tests `(.met // false) or (.failed // false)` on the last record (`:5823`).
  - If the result is `false`, the goal is live: it prints `.condition // ""` and returns 0 (`:5824-5825`).
  - Otherwise it returns 1 immediately (`:5827`) and **stops searching**. This covers a met goal, a failed goal, and a `/goal clear` marker (which carries met:true).
- If the goal was never armed (no `goal_status` lines, or only prose mentions), the rec is empty or the pipeline fails, which leads to `continue` (`:5819-5820`). The search **keeps going** through the remaining hits and roots, then returns 1 (`:5832`).
- A live record with an empty condition returns rc 0 with empty output. That is dropped by `[ -n "$_inh_cond" ] || return 0` (`:5846`).

## 6. Validating an inherited condition

**Which validator, and how it is called.** `inherit_recycle_goal` assigns `FIRE_GOAL="$_inh_cond"` (`:5847`) and then calls `check_goal_arm` with no arguments (`:5848`). The validator reads the global: `local cond="${FIRE_GOAL:-}"` (`:5735`). It is the same validator the explicit flag goes through at `:9015`.

**What it rejects, and why.**
- A condition containing a newline (`:5744-5750`). The arming paste submits at the first CR, so the rest would be left unsent in the composer.
- A condition that starts with `/` (`:5754-5758`). It is pasted as `/goal <cond>`, so it would read as another command.
- A condition longer than `${GOAL_MAX_CHARS:-4000}` characters (`:5759-5765`). The harness caps goal conditions at that length.

**What happens on refusal.**
- `FIRE_GOAL=""` (`:5852`), then `return 0` (`:5854`). The recycle continues without a goal.
- The warning is `echo "⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself …" >&2` (`:5851`), plus `check_goal_arm`'s own `!!` lines on stderr.

**Who can read that warning.**
- It is printed by the foreground `recycle_fire` process, before the watcher is detached (`:12628`). So it is not in the watcher log.
- It is also after the successor's brief copy was finished (`:10668-10848`). So it is not in the successor's brief either.
- In a self-recycle, the only reader is the predecessor's own Bash tool result, and `/exit` is typed into that same pane moments later (`:12723-12727`). The instruction "re-arm it yourself … in the relaunched session" reaches the session that is about to be killed, not the successor.

**What gets recorded.**
- `inherit_recycle_goal` itself writes nothing, and there is no `emit_goal_event` on this path.
- `check_goal_arm`'s refusal arms each call `emit_fire_refusal payload-goal-arm-{multiline,slash,cap}` (`:5748`, `:5756`, `:5763`). That calls `emit_fire_event refused … refuse payload` (`:758-760`, gate from `:742`), which appends a JSON line to `$HOME/.claude/logs/handoffs.jsonl` (`:683`, `:711`). The line carries `class:"refused"`, `engaged:false` and `refuse_reason` (`:702-703`).
- It is skipped if `CC_FIRE_REFUSAL_LOG=0` (`:684`) or jq is missing (`:686`).
- **This row is misleading:** it records a refused fire, but the recycle was not refused.

## 7. Where the call sits, and how the goal reaches the successor

**The single call site** is `inherit_recycle_goal "$rcy_old_sid"` at `:12540`, inside `recycle_fire` (`:12354`). `recycle_fire` is reached only from the non-dry `--recycle` branch (`:12915-12964`). A `--dry-run` goes down the `:12787` branch instead, so inheritance is never evaluated in a dry run. The resume-mode dry-run line says so explicitly (`:12796`).

**Immediately before the call:**
- The composer gate (`:12467-12507`).
- `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`:12524`).

**Immediately after the call:**
- `RCY_T0="$(date -u +%FT%T)"` (`:12542`).
- `pin_term_verdict_for_watcher` (`:12543`).
- Resolution of the source transcript, run dir and submit token (`:12555-12627`).
- `detach` of the watcher (`:12628`).

**The branch that deliberately skips inheritance** is `-n "$RESUME_LAUNCHER"` (`:12535-12538`). A same-uuid `--resume` already carries the unmet goal, so inheriting would arm the same condition twice in one session. The resume-mode dry-run readout says the same: "an unmet goal rides --resume" (`:12796`).

**A second, implicit skip:** if the pane is confirmed to be at a shell prompt, `recycle_fire` types the relaunch and returns at `:12441-12446`, before `:12540` and without a watcher. In that case neither an inherited nor an explicit goal is ever armed.

**How the condition travels:**
1. **Handoff.** `FIRE_GOAL` is passed as an argument to a detached re-run of the script: `detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" …` (`:12628`). Counting after `__recycle`, it is argument 8.
2. **Read back.** The watcher branch starts at `if [ "${1:-}" = "__recycle" ]` (`:6938`) and parses `FIRE_GOAL="${8:-}"` (`:7158`). The comment at `:6955-6956` enumerates the same order.
3. **Before arming, the watcher:**
   - waits for the old session to exit to a confirmed shell (`:6996-7132`);
   - types the relaunch command (`:7184`);
   - waits for a claude process to appear (`:7277-7310`);
   - polls for engagement, meaning a real assistant turn: `recycle_engaged "$RSID" "$RCY_OLD_SID" "$RCY_MARKER"`, or `resume_engaged` in resume mode (`:7339-7359`).
4. **Arming moment.** Only after "ENGAGEMENT CONFIRMED" (`:7360`) does it call `arm_goal "$IT2" "$RSID" "$FIRE_GOAL"` (`:7365`). So the goal is armed after the successor has begun working on its brief, as a second message.
5. **Inside `arm_goal`:**
   - It pastes `"/goal $cond"` with `it2_paste_submit_verified` (`:5886`).
   - Occupied composer, read-back mismatch and refused paste each produce their own verdict and a `cc-notify` to the pane (`:5889-5903`).
   - It then polls `goal_armed_for_pane` every `FIRE_GOAL_VERIFY_INTERVAL` (default 3s) for up to `FIRE_GOAL_VERIFY_TIMEOUT` (default 45s) (`:5866`, `:5905-5912`). That check resolves the successor's session id from the pane (`:5778`), finds its transcript under `CC_PROJECTS_DIRS`, and requires an attachment with `goal_status`, `met==false` and the exact condition (`:5792`).
   - The result is `verdict=set` (`:5907`) or `verdict=unverified` (`:5915`).
6. **When no arm happens.** If engagement never confirms, `arm_goal` is never called. Those arms call `goal_unreachable` instead (`:7333`, `:7397`, `:7446`); I did not read that function's body.
